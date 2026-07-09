#! /bin/sh

# a simple program to manage tasks executed in batch

# script options (recognized after ^#$ ): -N -o -e -wd -np -h -email
# -N: name of the job
# -o: file to store output messages
# -e: file to store error messages
# -wd: working directory
# -np: number of processors
# -h: hostname
# -email: where to send alert messages

: '# example of a valid job file:
#$ -N test job
#$ -o
#$ -e test.err
#$ -h hostname
#$ -email abc@email.com
#$ -np 3

n=0

echo $SQHOSTS

while [ $n -lt 15 ] ; do
    date
    sleep 5
    n=`expr $n + 1`
done
'

###########################################################

DEBUG=false
limitbyload=false

#hosts="localhost hostlocal"
#procs="3 2"
hosts="localhost"
procs="4"    # will get the number of processors automatically
#procs="3 2"

if [ -z "$hosts" ] ; then hosts="localhost " ; fi

if [ -z "$procs" ] ; then
    for host in $hosts ; do
        proc=""
        if [ "$host" = "localhost" ] ; then
            proc=`cat /proc/cpuinfo | grep processor | wc -l`
        else
            proc=`ssh $host cat /proc/cpuinfo | grep processor | wc -l`
        fi
        hostprocs=$hostprocs"$host:$proc,"
        procs="$procs$proc "
    done
fi

#if [ `whoami` = "root" ] ; then
#    basedir="/var/run/sq"
#else
    basedir=$HOME/.local/sq
#fi
if $DEBUG ; then
    basedir=$basedir".d"
fi

qlist="$basedir/qlist"  # queued jobs
rlist="$basedir/rlist"  # running jobs
elist="$basedir/elist"  # ended jobs
logfile="$basedir/log"

if   [ "$1" = "-h"   ] ; then
    echo "$0 [-install|-mon|-sub|-del|-stat|-o|-e]"
    exit
elif [ "$1" = "-install" ] ; then
    cp $0 /usr/local/bin
    ln -s /usr/local/bin/$(basename $0) /usr/local/bin/qmon
    ln -s /usr/local/bin/$(basename $0) /usr/local/bin/qsub
    ln -s /usr/local/bin/$(basename $0) /usr/local/bin/qdel
    ln -s /usr/local/bin/$(basename $0) /usr/local/bin/qstat
fi

if ! [ -d $basedir ] ; then mkdir $basedir ; fi
if ! [ -d $qlist ]   ; then mkdir $qlist   ; chmod a+rwx $qlist ; fi
if ! [ -d $rlist ]   ; then mkdir $rlist   ;                      fi
if ! [ -d $elist ]   ; then mkdir $elist   ; chmod a+rwx $elist ; fi

###########################################################
# assign a ticket, and include cwd, name, nprocs, logfile, command in queue list

qsub() {
    ticket=0

    eticket=`ls -v -1 $elist 2>/dev/null | tail -1`
    if [ -n "$eticket" ] ; then
        if [ "$ticket" -lt "$eticket" ] ; then
            ticket=$eticket
        fi
    fi
    rticket=`ls -v -1 $rlist 2>/dev/null | tail -1`
    if [ -n "$rticket" ] ; then
        if [ "$ticket" -lt "$rticket" ] ; then
            ticket=$rticket
        fi
    fi
    qticket=`ls -v -1 $qlist 2>/dev/null | tail -1`
    if [ -n "$qticket" ] ; then
        if [ "$ticket" -lt "$qticket" ] ; then
            ticket=$qticket
        fi
    fi

    ticket=`expr $ticket + 1`
    echo "$ticket queued"

#   cp "$1" $qlist/$ticket
    cat "$1" > $qlist/$ticket

    name=$ticket
#   if [ -z "`grep '^#$ -N' $qlist/$ticket`" ] ; then
#       echo "#$ -N -" >> $qlist/$ticket
#   else
    if [ -n "`grep '^#$ -N' $qlist/$ticket`" ] ; then
        name=`grep '^#$ -N' $qlist/$ticket | cut -d' ' -f3`
    fi
    if [ -z "`grep '^#$ -wd' $qlist/$ticket`" ] ; then
        echo "#$ -wd `pwd`" >> $qlist/$ticket
    fi
    if [ -z "`grep '^#$ -np' $qlist/$ticket`" ] ; then
        np=`cat $qlist/$ticket | grep "mpirun" | sed -n "s/.* -np \([0-9]*\).*/\1/p" | sort | tail -1`  # try to get np automatically if the task is to be executed with mpirun
        if [ -z "$np" ] ; then
            np=1
        fi
        echo "#$ -np $np" >> $qlist/$ticket
    fi
    if [ -n "`grep '^#$ -o$' $qlist/$ticket`" ] ; then
        sed -i "s%^#$ -o%#$ -o /tmp/$name.out%" $qlist/$ticket
    fi
    if [ -n "`grep '^#$ -e$' $qlist/$ticket`" ] ; then
        sed -i "s%^#$ -e%#$ -e /tmp/$name.err%" $qlist/$ticket
    fi

    echo "#$ submitted `date +%F\ %R`" >> $qlist/$ticket
    exit
}

if [ `basename "$0"` = "qsub" ] ; then
    qsub $1
elif [ "$1" = "-sub" ] ; then
    qsub $2
fi

###########################################################
# remove task

qdel() {
    if [ -e $qlist/$1 ] ; then
        echo "# `date +%F\ %R`: removed from queue" >> $qlist/$1
        mv $qlist/$1 $elist
    elif [ -e $rlist/$1 ] ; then
        touch $qlist/$1.del
    elif [ -e $elist/$1 ] ; then
        echo "$1 already ended"
    else
        echo "$1 not found"
    fi
    exit
}

if [ `basename "$0"` = "qdel" ] ; then
    qdel $1
elif [ "$1" = "-del" ] ; then
    qdel $2
fi

###########################################################
# list processes sorting by $qlist and $rlist

print_logs() {
    if [ -e $rlist/$2 ] ; then
        lticket=$rlist/$2
    elif [ -e $elist/$2 ] ; then
        lticket=$elist/$2
    else
        exit
    fi
    log=`cat $lticket | grep "^#$ $1 " | cut -d' ' -f3`
    if [ -n "$log" ] ; then
        tail -100 "$log"
        ls -l "$log"
    fi
    exit
}

print_job() {
    if [ -e $rlist/$1 ] ; then
        cat $rlist/$1
    elif [ -e $elist/$1 ] ; then
        cat $elist/$1
    elif [ -e $qlist/$1 ] ; then
        cat $qlist/$1
    fi
}

if [ "$1" = "-log" ] ; then
    if [ "$2" -gt 0 ] ; then
        print_job $2
    else
        tail -100 $logfile
    fi
    exit
elif [ "$1" = "-o" ] ; then
    print_logs -o $2
elif [ "$1" = "-e" ] ; then
    print_logs -e $2
fi

print_stats() {
#   for aticket in `ls -v $1/* --hide *.del 2>/dev/null` ; do
    for aticket in `ls -t -r $1/* --hide *.del 2>/dev/null` ; do
        np=`cat $aticket  | grep "#$ -np" | cut -d' ' -f3-`
        name=`cat $aticket | grep "#$ -N" | cut -d' ' -f3-`
        host=`cat $aticket | grep "#$ -h" | tail -1 | cut -d' ' -f3-`
        if [ -z "$host" ] ; then
            host=`cat $aticket | grep "#$ +host" | tail -1 | cut -d' ' -f3-`
        fi
        if [ "$1" = "$rlist" ] ; then
            user=`cat $aticket | grep "#$ +user" | tail -1 | cut -d' ' -f3-`
        elif [ "$1" = "$qlist" ] ; then
            user="$(stat --format '%U' $aticket)"
        fi
        ticket=$(basename $aticket)
#       ticket="${ticket%.*}"
        if [ -e $qlist/$ticket.del ] ; then
            echo "$ticket	$name	$user	del	$np	$host"
        else
            echo "$ticket	$name	$user	$2	$np	$host"
        fi
    done
}

qstat() {
    echo "ticket	name	user	status	procs	host"
    print_stats $rlist "running"
    print_stats $qlist "queued"
#   print_stats $elist "ended"
    exit
}

if [ `basename "$0"` = "qstat" ] ; then
    qstat # $1 $2
elif [ "$1" = "-stat" ] ; then
    qstat # $2 $3
fi

###########################################################

check_qdel() {
    for dticket in `ls -v $qlist/*.del 2>/dev/null` ; do
        user1="$(stat --format '%U' $dticket)"
        ticket=$(basename $dticket)
        ticket="${ticket%.*}"
        rticket=$rlist/$ticket
        if [ -e $rticket ] ; then
            host=`cat $rticket   | grep "^#$ +host " | tail -1 | cut -d' ' -f3`
            user2=`cat $rticket  | grep "^#$ +user " | tail -1 | cut -d' ' -f3`
            if [ "$user1" = "$user2" ] ; then
                pid=`cat $rticket | grep "^#$ +pid " | tail -1 | cut -d' ' -f3`
#               if [ -z "$host" ] || [ "$host" = "localhost" ]; then
                    kill $pid
#               else
#                   ssh $user1@$host kill $pid
#               fi
                echo "#$ killed `date +%F\ %R`" >> $rticket
                echo "$ticket killed `date +%F\ %R`" | tee -a $logfile
                sleep 1
            fi
        else
            echo "$ticket not found `date +%F\ %R`" | tee -a $logfile
        fi
        rm $dticket
    done
}

check_done_jobs() {
    for rticket in `ls -v $rlist/* 2>/dev/null` ; do
        rhost=`cat $rticket | grep "^#$ +host "  | tail -1 | cut -d' ' -f3`
        pid=`  cat $rticket | grep "^#$ +pid "   | tail -1 | cut -d' ' -f3`
        email=`cat $rticket | grep "^#$ -email " | tail -1 | cut -d' ' -f3`
        running=false
#       if [ $rhost = "localhost" ] ; then
            if [ -d /proc/$pid ] ; then
                running=true
            fi
#       else
#           if [ -n `ssh $rhost "ls /proc/$pid"` ] ; then # FIXME check network nodes...
#               running=true
#           fi
#       fi
#echo "check_done_jobs $rticket $rhost $pid $running"
        if ! $running ; then
            ticket=`basename $rticket`
            echo "#$ ended `date +%F\ %R`" >> $rticket
            echo "$ticket ended @$rhost `date +%F\ %R`" >> $logfile # | tee -a $logfile
            mv $rticket $elist
            if [ -n "$email" ] ; then # email owner
                echo "process $ticket ended at `date`." | mailmail -s "[sq] $ticket" $email
            fi
        fi
    done
}

update_free_procs() {
    host=$1
    freeproc=$2    # assume that all existing cores are free, then discount those occupied by jobs
    for rticket in `ls -v $rlist/* 2>/dev/null` ; do
        ticket=$(basename $rticket)
        rhost=`cat $rticket | grep "^#$ +host "  | tail -1 | cut -d' ' -f3`
        if ! [ "$rhost" = "$host" ]; then
            continue
        fi
        np=`   cat $rticket | grep "^#$ -np "    | tail -1 | cut -d' ' -f3`
#       pid=`  cat $rticket | grep "^#$ +pid "   | tail -1 | cut -d' ' -f3`
#       email=`cat $rticket | grep "^#$ -email " | tail -1 | cut -d' ' -f3`
        freeproc=`expr $freeproc - $np`
#echo "update_free_procs $rticket $rhost $pid $freeproc" >&2
    done
#   if [ $freeproc -lt 0 ] ; then
#       freeproc=0
#   fi
    if ! $limitbyload ; then
        echo $freeproc
        return
    fi
    if [ "$host" = "localhost" ] ; then
        load=`uptime | sed 's/.*load average: \([0-9]*\).*/\1/'`
    else
        load=`ssh $host uptime | sed 's/.*load average: \([0-9]*\).*/\1/'`
    fi
    if $DEBUG ; then
        echo "$host $2 $freeproc" >> $logfile
    fi
    if [ -z "$load" ] ; then # if no connection to host, return 0 free processors
        echo 0
        return
    fi
    idle=`expr $freeproc - $load`
    if $DEBUG ; then
        echo "idle $idle" >> $logfile
    fi
    if [ $idle -lt 0 ] ; then idle=0; fi
    if [ $idle -gt $freeproc ] ; then
        echo $freeproc
    else
        echo $idle
    fi
}

run_job() {
    host=$1
    freeproc=$2
#   for qticket in $qlist/* ; do
    for qticket in `ls -v $qlist/* 2>/dev/null` ; do
        qhost=`cat $qticket | grep "^#$ -h "  | cut -d' ' -f3`
        if [ -n "$qhost" ] ; then
            if [ "$qhost" != "$host" ] ; then
                continue
            fi
        fi
        np=`cat $qticket | grep "^#$ -np" | cut -d' ' -f3`
        if [ $np -le $freeproc ] ; then
#echo "run_job $qticket $np $freeproc" >&2
            rticket=$rlist/$(basename $qticket)
            user="$(stat --format '%U' $qticket)"
# sanitize user and pid from script
            sed -i "s/^#$ +user .*//;s/^#$ +pid .*//" $qticket
            mv $qticket $rticket
            echo "#$ started `date +%F\ %R`" >> $rticket
            if [ "$user" != "root" ] ; then
                echo "#$ +user $user"        >> $rticket
            fi
            echo "$(basename $rticket) started @$host `date +%F\ %R`" | tee -a $logfile
#           echo "mv $rticket $elist"        >> $rticket # if jobs manager goes down, the own job moves itself to 'done'
            cwd=`cat $rticket | grep "^#$ -wd " | cut -d' ' -f3`
            log=`cat $rticket | grep "^#$ -o "  | cut -d' ' -f3`
            err=`cat $rticket | grep "^#$ -e "  | cut -d' ' -f3`
            if [ -z "$log" ] ; then
                log="/dev/null"
            fi
            if [ -z "$err" ] ; then
                err="/dev/null"
            fi
            n=0
            SQHOSTS=""
            while [ $n -lt $np ] ; do
                if [ -z "$SQHOSTS" ] ; then
                    SQHOSTS="$host"
                else
                    SQHOSTS="$SQHOSTS,$host"
                fi
                n=`expr $n + 1`
            done
            export SQHOSTS
            echo "#$ +host $host" >> $rticket
            chown `whoami`.`whoami` $rticket
            chmod 755 $rticket
            if [ "$host" = "localhost" ] ; then
                if [ `whoami` = "root" ] ; then
                    runuser $user -c "cd '$cwd' && sh $rticket 1> $log 2> $err" &
                else # only the own user is able to submit jobs
                    cd "$cwd" && sh $rticket 1> $log 2> $err &
                fi
            else
                tmpticket="/tmp/"$(basename $rticket)
                scp $user@$host $rticket $tmpticket
#               ssh $user@$host "cd '$cwd' && sh $tmpticket 1> $log 2> $err" &  # PID is on the server machine, not in the host
                if [ `whoami` = "root" ] ; then
                    runuser $user -c "ssh $host \"cd \\\"$cwd\\\" && sh $tmpticket" 1> $log 2> $err &
                else
                    ssh $host "cd \"$cwd\" && sh $tmpticket" 1> $log 2> $err &
#                   cd "$cwd" && sh $rticket 1> $log 2> $err &
                fi
#               ssh $user@$host "rm $tmpticket"
            fi
            echo "#$ +pid $!" >> $rticket
            freeproc=`expr $freeproc - $np`
        fi
        if [ $freeproc = 0 ] ; then
            break
        fi
    done
}

restore_jobs() {
    for rticket in `ls -v $rlist/* 2>/dev/null` ; do
        pid=`cat $rticket | grep "^#$ +pid" | tail -1 | cut -d' ' -f3`
        if [ -d /proc/$pid ] ; then
            continue
        fi
        echo "#$ rescheduled `date +%F\ %R`" >> $rticket
        mv $rticket $qlist
    done
}

# main loop
qmon() {
    restore_jobs
    while true ; do
        check_qdel
        check_done_jobs
        hostnum=0
        hostfreeprocs=""
        while true ; do
            hostnum=`expr $hostnum + 1`
            host=`echo "$hosts " | cut -d' ' -f$hostnum`
            proc=`echo "$procs " | cut -d' ' -f$hostnum`
            if [ -z "$host" ] ; then
                break
            fi
            freeproc=`update_free_procs $host $proc`
#echo "qmon $host $proc #$freeproc#" >&2
            if [ $freeproc = 0 ] ; then
                continue
            fi
#           run_job $host $freeproc
##################################################
            hostfreeprocs="$freeproc@$host\n$hostfreeprocs"
sleep 1
        done
#       if [ -n "$hostfreeprocs" ] ; then
        sortedhp=`echo $hostfreeprocs | sort -n`
        for sorted in $sortedhp; do
            freeproc=`echo $sorted | cut -d'@' -f1`
            host=`echo $sorted | cut -d'@' -f2-`
#echo "qmon $sorted // $host $freeproc" >&2
            run_job $host $freeproc
        done
#       fi
        touch $logfile
        sleep 60
    done
}

last=`stat -c %Y $logfile`
now=`date +%s`
diff=`expr $now - $last`
if [ $diff -lt 120 ] ; then
    echo "$0 still running"
    exit
fi

if [ `basename "$0"` = "qmon" ] ; then
    qmon
elif [ "$1" = "-mon" ] ; then
    qmon
fi

