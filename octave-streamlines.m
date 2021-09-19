% https://github.com/leorosa/octave-streamlines/

function yout = rk2(ydot, xend, h, y0)
    x = 0:h:xend;
    n = length(x);
    yout = zeros(n,size(y0,2));
    yout(1,:) = y0;
    y = y0;
    for i=2:n
        k = ydot(x(i), y);
        y = y + h * ydot(x(i), y+(h/2)*k);
        yout(i,:) = y;
    end
end

function ydot = vel(t, pos)
    global x y u v
    ydot(1) = interp2(x, y, u, pos(1), pos(2));
    ydot(2) = interp2(x, y, v, pos(1), pos(2));
end

function streamlines(seedx, seedy, tend, dt)
    hold on
    for i=1:length(seedx)
        pos = rk2(@vel, tend, dt, [seedx(i),seedy(i)]);
        plot(pos(:,1),pos(:,2), 'k')
    end
    hold off
end

%%% EXAMPLE
global x y u v
[x,y] = meshgrid(1:10,1:10);
u = 2*rand(10)-rand(10);
v = 5*rand(10);
seedx = x(1,:);
seedy = ones(1,10);

figure(1)
quiver(x, y, u, v)
figure(2)
%streamlines(originx, originy, tend, dt)
streamlines(seedx, seedy, 10, 0.1)
