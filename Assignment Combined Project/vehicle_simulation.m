function [ output ] = vehicle_simulation( vehicle_params, general_params, drv_mission, pass_flow )
%VEHICLE_SIMULATION Summary of this function goes here
%   Detailed explanation goes here

output = struct;
output.e_traction_tot_kWh = 0;
output.e_brake_tot_kWh = 0;
output.e_tot_kWh = 0;
output.P_traction_max_kW = 0;
output.P_brake_max_kW = 0;
output.P_max_kW = 0;
output.t_round_trip = 0;
output.t_charging = 0;

simulated_drive_cycles = [1, 2];

%% Load passenger and drive cycle data
hr = pass_flow.x;
yA = pass_flow.yA;
yB = pass_flow.yB;
dc = drv_mission.dc;
dc.dist = dc.s;
dc = rmfield(dc,'s');

%% Calculate supporting variables
qAB = yA - yB; % Net flow from A to B [passengers/hour]
q = min([yA, yB],[],2); % Base flow of passengers (directionless) [passengers/hour]
l = diff(dc.dist);
M = [0.5*eye(length(dc.slope)-1) zeros(length(dc.slope)-1,1)] + [zeros(length(dc.slope)-1,1) 0.5*eye(length(dc.slope)-1)]; % Mean adjacent value matrix
a = M*dc.slope; 
dc.pos = cumsum([0; l.*cos(a)]); % Flight distance [m]
dc.alt = cumsum([dc.altinit; l.*sin(a)]);
amax = general_params.v_max_kmh/3.6/general_params.t_zerotomax; % Maximum allowed acceleration [m/s^2]

% Generate simple accelerate-vmax-decelerate velocity profile
t0 = 0;
t1 = general_params.v_max_kmh/3.6/amax;
t2 = (dc.dist(end) + (general_params.v_max_kmh/3.6)^2/amax)/(general_params.v_max_kmh/3.6);
t3 = t2 + general_params.v_max_kmh/3.6/amax;
t = (0:t3)';
v = amax*t;
v(v>general_params.v_max_kmh/3.6) = 0;
v = v + flipud(v);
v(v==0) = general_params.v_max_kmh/3.6;
v(1) = 0; 
v(end) = 0;

%% Ideal vehicle
%------------------------------------------------
% Components and Systems for Electromobility
% - Practical session I
% 
% Script file for running idealvehicle.mdl
% - Ideal powertrain, 100% efficiency
%------------------------------------------------

%------------------------------------------------
% Vehicle parameters
%------------------------------------------------
% Combustion engine parameters  ++++++++++++++++++
T_max = inf;
% Fuel energy density in [Ws/liter]
Density = 27.78; % Gasoline 
nP = vehicle_params.n_pass;
Mv = vehicle_params.m_kg + nP*general_params.m_pass_kg; % Vehicle weight
rw = vehicle_params.rw; % Wheel radius (m)
Cd = vehicle_params.Cd; % Air resistance
Cr = vehicle_params.Cr;	% Roll resistance
Av = vehicle_params.Ad;	% Front area
vmax=vehicle_params.v_max_kmh / 3.6; % Max velocity
Pmax=vehicle_params.P_max_kW * 1000; % Max power

%------------------------------------------------
% Environment parameters
%------------------------------------------------
rho_air = 1.2;              % Air density
grav = 9.81;                % Gravitation

% Simulate vehicle
for i = simulated_drive_cycles
    [cycle, endtime, cycle_name] = select_cycle(i, dc, t, v);
    
    %% Simulate vehicle
    options = simset('SrcWorkspace','current');
    sim('idealvehicle',[],options);
    
    %% Energy analysis 
    EnergyTraction_tot = Energy.signals(1).values(end);
    EnergyBrake_tot = Energy.signals(4).values(end);
    MaxTractionPower = max(abs(Power.signals(3).values));
    MaxBrakingPower = max(abs(Power.signals(5).values));
    tTrip = endtime;
    
    %% Add results to output
    output.E_traction_tot_kWh = output.e_traction_tot_kWh + EnergyTraction_tot /60/60/1000;
    output.E_brake_tot_kWh = output.e_brake_tot_kWh + EnergyBrake_tot /60/60/1000;
    output.P_traction_max_kW = max([output.P_traction_max_kW, MaxTractionPower / 1000]);
    output.P_brake_max_kW = max([output.P_brake_max_kW, MaxBrakingPower / 1000]);
    output.t_round_trip = output.t_round_trip + tTrip;
    
    %% Charging time calculation
    output.t_charging_round_trip = output.t_charging + (EnergyTraction_tot-EnergyBrake_tot)/60/60/1000/vehicle_params.E_batt_kWh/general_params.C_rate*60*60;
end
output.P_max_kW = max([output.P_traction_max_kW, output.P_brake_max_kW]);
output.E_tot_kWh = output.E_traction_tot_kWh - output.E_brake_tot_kWh;
end

function [ cycle, endtime, cycle_name ] = select_cycle ( idx, dc, t, v )
%------------------------------------------------
% Convert topology to drive cycle
%------------------------------------------------
Drive_cycles = cellstr(['A to B'; 'B to A']);
cycle = zeros(length(t),5);
switch idx
	case 1
		cycle(:,1) = t;
		cycle(:,2) = v;
		cycle(:,3) = cumsum(v);
		cycle(:,4) = interp1(dc.dist,dc.alt,cycle(:,3),'pchip');
		cycle(:,5) = interp1(dc.dist,dc.slope,cycle(:,3),'pchip');
	case 2
		cycle(:,1) = t;
		cycle(:,2) = v;
		cycle(:,3) = flipud(cumsum(v));
		cycle(:,4) = flipud(interp1(dc.dist,dc.alt,cycle(:,3),'pchip'));
		cycle(:,5) = -1*flipud(interp1(dc.dist,dc.slope,cycle(:,3),'pchip'));
end
cycle_name = Drive_cycles(idx);
endtime = max(cycle(:,1));
end

