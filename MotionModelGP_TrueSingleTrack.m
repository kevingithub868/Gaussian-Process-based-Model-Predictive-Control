%------------------------------------------------------------------
% Programed by: 
%   - Lucas Rath (lucasrm25@gmail.com)
%   - 
%   -
%------------------------------------------------------------------

classdef MotionModelGP_TrueSingleTrack < MotionModelGP
%--------------------------------------------------------------------------
%   xk+1 = fd(xk,uk) + Bd * ( d(zk) + w ),    
%
%       where: zk = Bz*xk,
%              d ~ N(mean_d(zk),var_d(zk))
%              w ~ N(0,sigmaw)
%
%   
%   x = [...]'   
%   u = [...]'               
%   
%--------------------------------------------------------------------------
 
    properties
        M=1239; % vehicle mass
        g=9.81; % gravitation
        l_f=1.19016; % distance of the front wheel to the center of mass
        l_r=1.37484; % distance of the rear wheel to the center of mass
        %l=l_f+l_r; % vehicle length (obsolete)
        R=0.302; % wheel radius
        I_z=1752; % vehicle moment of inertia (yaw axis)
        I_R=1.5; % wheel moment of inertia
        i_g=[3.91 2.002 1.33 1 0.805]; % transmissions of the 1st ... 5th gear
        i_0=3.91; % motor transmission
        B_f=10.96; % stiffnes factor (Pacejka) (front wheel)
        C_f=1.3; % shape factor (Pacejka) (front wheel)
        D_f=4560.4; % peak value (Pacejka) (front wheel)
        E_f=-0.5; % curvature factor (Pacejka) (front wheel)
        B_r=12.67; %stiffnes factor (Pacejka) (rear wheel)
        C_r=1.3; %shape factor (Pacejka) (rear wheel)
        D_r=3947.81; %peak value (Pacejka) (rear wheel)
        E_r=-0.5; % curvature factor (Pacejka) (rear wheel)
        f_r_0=0.009; % coefficient (friction)
        f_r_1=0.002; % coefficient (friction)
        f_r_4=0.0003; % coefficient (friction)
    end
    
    properties(SetAccess=private)
        Bd = [0 0 1 0 0 0 0 0 0 0]';       % xk+1 = fd(xk,uk) + Bd*d(zk)
        Bz = eye(10)        % z = Bz*x     
        n = 10              % number of outputs x(t)
        m = 5               % number of inputs u(t)
    end
    
    methods
        function obj = MotionModelGP_TrueSingleTrack(d,sigmaw)
        %------------------------------------------------------------------
        %   object constructor
        %------------------------------------------------------------------
            % call superclass constructor
            obj = obj@MotionModelGP(d,sigmaw);
        end
        
        function [xdot, grad_xdot] = f (obj, x, u)
        %------------------------------------------------------------------
        %   Continuous time dynamics of the single track (including
        %   disturbance):
        %------------------------------------------------------------------
            
            sx = x(1);
            sy = x(2);
            v = x(3);
            beta = x(4);
            psi = x(5);
            omega = x(6);
            x_dot = x(7);
            y_dot = x(8);
            psi_dot = x(9);
            varphi_dot = x(10);
            
            if v<0
                v = 0;
            end
            delta = u(1);  % steering angle
            G     = 1; %u(2);  % gear
            F_b    = u(3);  % brake force
            zeta  = u(4);  % brake force distribution
            phi   = u(5);  % acc pedal position
            
            % input constraints
            if delta>0.53 % upper bound for steering angle exceeded?
                delta=0.53; % upper bound for steering angle
            end
            if delta<-0.53 % lower bound for steering angle exceeded?
                delta=-0.53; % lower bound for steering angle
            end
            if F_b<0 % lower bound for braking force exceeded?
                F_b=0; % lower bound for braking force
            end
            if F_b>15000 % upper bound for braking force exceeded?
                F_b=15000; % upper bound for braking force 
            end
            if zeta<0 % lower bound for braking force distribution exceeded?
                zeta=0; % lower bound for braking force distribution 
            end
            if zeta>1 % upper bound for braking force distribution exceeded?
                zeta=1; % upper bound for braking force distribution
            end
            if phi<0 % lower bound for gas pedal position exceeded?
                phi=0; % lower bound for gas pedal position
            end
            if phi>1 % upper bound for gas pedal position exceeded?
                phi=1; % upper bound for gas pedal position
            end

           %% slip
            %slip angles and steering
            a_f=delta-atan((obj.l_f*psi_dot-v*sin(beta))/(v*cos(beta))); % front slip angle
            a_r=atan((obj.l_r*psi_dot+v*sin(beta))/(v*cos(beta))); %rear slip angle
            %if af>ar %understeering?
            %steering='understeering';
            %end
            %if af<ar %oversteering?
            %steering='oversteering';
            %end
            %if af=ar %neutral steering?
            %steering='neutral';
            %end
            if isnan(a_f) % front slip angle well-defined?
                a_f=0; % recover front slip angle
            end
            if isnan(a_r) % rear slip angle well-defined
                a_r=0; % recover rear slip angle
            end
            %wheel slip
            if v<=obj.R*varphi_dot % traction slip? (else: braking slip)
                S=1-(v/(obj.R*varphi_dot)); %traction wheel slip
            else
                S=1-((obj.R*varphi_dot)/v); % braking slip
            end
            if isnan(S) % wheel slip well-defined?
                S=0; % recover wheel slip
            end
            S=0; % neglect wheel slip

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %% traction, friction, braking
            
            n=v*obj.i_g(G)*obj.i_0*(1/(1-S))/obj.R; % motor rotary frequency
            if isnan(n) % rotary frequency well defined?
                n=0; %recover rotary frequency
            end
            if n>(4800*pi)/30 % maximal rotary frequency exceeded?
                n=(4800*pi)/30; % recover maximal rotary frequency
            end
            T_M=200*phi*(15-14*phi)-200*phi*(15-14*phi)*(((n*(30/pi))^(5*phi))/(4800^(5*phi))); % motor torque
            M_wheel=obj.i_g(G)*obj.i_0*T_M; % wheel torque
            F_w_r=(obj.M*obj.l_f*obj.g)/(obj.l_f+obj.l_r); % weight rear
            F_w_f=(obj.M*obj.l_r*obj.g)/(obj.l_f+obj.l_r); % weight front
            f_r=obj.f_r_0+obj.f_r_1*(abs(v)*3.6)/100+obj.f_r_4*((abs(v)*3.6)/100)^4; % approximate friction
            F_b_r=zeta*F_b; % braking force rear
            F_b_f=F_b*(1-zeta); % braking force front
            F_f_r=f_r*F_w_r; % friction rear
            F_f_f=f_r*F_w_f; % friction front
            F_x_r=(M_wheel/obj.R)-sign(v*cos(beta))*F_b_r-sign(v*cos(beta))*F_f_r; % longitudinal force rear wheel
            F_x_f=-sign(v*cos(beta))*F_b_f-sign(v*cos(beta))*F_f_f; % longitudinal force front wheel
            F_y_r=obj.D_r*sin(obj.C_r*atan(obj.B_r*a_r-obj.E_r*(obj.B_r*a_r-atan(obj.B_r*a_r)))); % rear lateral force
            F_y_f=obj.D_f*sin(obj.C_f*atan(obj.B_f*a_f-obj.E_f*(obj.B_f*a_f ...
                             -atan(obj.B_f*a_f)))); % front lateral force

            %%
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% OUTPUT %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %% vector field (right-hand side of differential equation)
            x_dot=v*cos(psi-beta); % longitudinal velocity
            y_dot=v*sin(psi-beta); % lateral velocity
            v_dot=(F_x_r*cos(beta)+F_x_f*cos(delta+beta)-F_y_r*sin(beta) ...
                               -F_y_f*sin(delta+beta))/obj.M; % acceleration
            beta_dot=omega-(F_x_r*sin(beta)+F_x_f*sin(delta+beta)+F_y_r*cos(beta) ...
                                        +F_y_f*cos(delta+beta))/(obj.M*v); % side slip rate
            psi_dot=omega; % yaw rate
            omega_dot=(F_y_f*obj.l_f*cos(delta)-F_y_r*obj.l_r ...
                     +F_x_f*obj.l_f*sin(delta))/obj.I_z; % yaw angular acceleration
            x_dot_dot=(F_x_r*cos(psi)+F_x_f*cos(delta+psi)-F_y_f*sin(delta+psi) ...
                    -F_y_r*sin(psi))/obj.M; % longitudinal acceleration
            y_dot_dot=(F_x_r*sin(psi)+F_x_f*sin(delta+psi)+F_y_f*cos(delta+psi) ...
                    +F_y_r*cos(psi))/obj.M; % lateral acceleration
            psi_dot_dot=(F_y_f*obj.l_f*cos(delta)-F_y_r*obj.l_r ...
                      +F_x_f*obj.l_f*sin(delta))/obj.I_z; % yaw angular acceleration
            varphi_dot_dot=(F_x_r*obj.R)/obj.I_R; % wheel rotary acceleration
            if isnan(beta_dot) || isinf(beta_dot) % side slip angle well defined?
                beta_dot=0; % recover side slip angle
            end
            
            % calculate xdot and gradient
            xdot  = [x_dot; y_dot; v_dot; beta_dot; psi_dot; omega_dot; x_dot_dot; y_dot_dot; psi_dot_dot; varphi_dot_dot];
            grad_xdot = zeros(obj.n);
            
            if any(isnan(xdot)) || any(isinf(xdot)) || any(~isreal(xdot))
                l
            end
        end
        

        function r = ref(obj, tk, xk, t_r, t_l)
            %     xk = [2,1]';
            % calculate trajectory center line
            t_c = (t_r + t_l)/2;
            % find closest trajectory point w.r.t. the vehicle
            [~,idx] = min( pdist2(xk',t_c,'seuclidean',[1 1].^0.5).^2 );
            % set target as 3 poins ahead
            idx_target = idx + 10;
            % loop around when track is over
            idx_target = mod(idx_target, size(t_c,1));
            % return reference signal
            r = t_c(idx_target,:);
        end


    end
end
