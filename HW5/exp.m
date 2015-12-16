clear all
clc

exp_x=0;
factorial=1;
x_power=1;

x=3;

 fprintf('********** x=3 *********\n');
for nn=1:10
    exp_x=floor(exp_x+(x_power*32)/factorial);
	x_power = x_power*x;
	factorial = factorial*nn;
    exp_x_bin=dec2bin(exp_x,10);
	fprintf('k=%d, exp_x_bin=%s\n',(nn-1), exp_x_bin);
end