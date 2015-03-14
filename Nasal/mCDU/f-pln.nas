# LAT and VER REV pages are managed separately

var rm_route = "/autopilot/route-manager/";

var f_pln_disp = "/instrumentation/mcdu/f-pln/disp/";

var f_pln = {
	updating_wpts: 0,
	init_f_pln : func {
	
		# Completely Clear Route Manager, add the new waypoints from 'active_rte' and then add the departure and arrival icaos.
		
		# NOTE: Flightplans are only (re-)initialized when switched between active and secondary, and re-initialized after SID (- F-PLN DISCONTINUITY -)
		
		## RESET Terminal Procedure Manager
		
		me.route_manager = fmgc.RouteManager;
		
		fmgc.procedure.reset_tp();
		
		## Deactivate Route Manager
		
		setprop(rm_route~ "active", 0);
		
		## Clear the Route Manager
		
		setprop(rm_route~ "input", "@CLEAR");
		
		## Remove Departure and Destination
		
		setprop(rm_route~ "departure/airport", "");
		setprop(rm_route~ "destination/airport", "");
		setprop(rm_route~ "departure/runway", "");
		setprop(rm_route~ "destination/runway", "");
		
		setprop(f_pln_disp~ 'current-flightplan', '');
		setprop(f_pln_disp~ 'departure', '');
		setprop(f_pln_disp~ 'destination', '');
	
		me.route_manager.deleteFlightPlan('temporary');
		
		## Copy Waypoints and altitudes from active-rte
		
		for (var index = 0; getprop(active_rte~ "route/wp[" ~ index ~ "]/wp-id") != nil; index += 1) {
		
			var wp_id = getprop(active_rte~ "route/wp[" ~ index ~ "]/wp-id");
			
			var wp_alt = getprop(active_rte~ "route/wp[" ~ index ~ "]/altitude-ft");
		
			if (wp_alt == nil)
				wp_alt = 10000;
		
			setprop(rm_route~ "input", "@INSERT99:" ~ wp_id ~ "@" ~ wp_alt);
		
		}
		
		# Copy Speeds to Route Manager Property Tree
		
		var max_wp = getprop(rm_route~ "route/num");
		
		for (var wp = 0; wp < max_wp; wp += 1) {
		
			var wp_spd = getprop(active_rte~ "route/wp[" ~ wp ~ "]/ias-mach");
			
			if (wp_spd != nil)
				setprop(rm_route~ "route/wp[" ~ wp ~ "]/ias-mach", wp_spd);
		
		}
		
		## Reset Departure and Destination from active RTE
		
		var dep = getprop(active_rte~ "depicao");
		
		var arr = getprop(active_rte~ "arricao");
		
		setprop(rm_route~ "departure/airport", dep);
		setprop(rm_route~ "destination/airport", arr);
		
		setprop(f_pln_disp~ 'departure', dep);
		setprop(f_pln_disp~ 'destination', arr);

		if(getprop("/flight-management/alternate/icao") == "empty") {
			# artix: disabled this
                        #setprop(rm_route~ "input", "@INSERT99:" ~ dep ~ "@0");
		
		} else {
		
			setprop(rm_route~ "input", "@INSERT99:" ~ getprop("/flight-management/alternate/icao") ~ "@0");
		
		}
		
		## Calculate Times to each WP starting with FROM at 0000 and using determined speeds
		
		setprop(rm_route~ "route/wp/leg-time", 0);
		
		for (var wp = 1; wp < getprop(rm_route~ "route/num"); wp += 1) {
		
			var dist = getprop(rm_route~ "route/wp[" ~ (wp - 1) ~ "]/leg-distance-nm");
			
			var spd = getprop(rm_route~ "route/wp[" ~ wp ~ "]/ias-mach");
			
			var alt = getprop(rm_route~ "route/wp[" ~ wp ~ "]/altitude-ft");
			
			var gs_min = 0; # Ground Speed in NM/min
			
			if ((spd == nil) or (spd == 0)) {
			
				# Use 250 kts if under FL100 and 0.78 mach if over FL100
				
				if (alt <= 10000)
					spd = 250;
				else
					spd = 0.78;
			
			}		
			
			# MACH SPEED
			
			if (spd < 1) {
			
				gs_min = 10 * spd;
			
			}
			
			# AIRSPEED
			
			else {
			
				gs_min = spd + (alt / 200);
			
			}
			
			# Time in Minutes (rounded)
			
			var time_min = int(dist / gs_min);
			
			var last_time = getprop(rm_route~ "route/wp[" ~ (wp - 1) ~ "]/leg-time") or 0;
			
			if (wp == 1)
			    last_time = last_time + 30;
				
			# Atm, using 30 min for taxi time. You will be able to change this in INIT B when it's completed
			
			var total_time = last_time + time_min;
			
			setprop(rm_route~ "route/wp[" ~ wp ~ "]/leg-time", total_time);
		
		}
		var fp = flightplan();
		var sz = fp.getPlanSize();
		var first_wp = fp.getWP(0);
		if(sz > 1){
			if(sz == 2){
				me.route_manager.setDiscontinuity(first_wp.id);
			} else {
				var first_route_wp = fp.getWP(1);
				if(first_route_wp.wp_role != 'sid')
					me.route_manager.setDiscontinuity(first_wp.id);
				var last_route_wp = me.route_manager.getLastEnRouteWaypoint();
				if(last_route_wp != nil)
					me.route_manager.setDiscontinuity(last_route_wp.id);
			}
		}
		me.update_disp();
		
		setprop("/autopilot/route-manager/current-wp", 0);
		setprop("instrumentation/efis/inputs/plan-wpt-index", 0);
		setprop("instrumentation/efis[1]/inputs/plan-wpt-index", 0);
		#setprop(rm_route~ "active", 1); # TRICK: refresh canvas
		#setprop(rm_route~ "active", 0);
	
	},
	
	cpy_to_active : func {
	
		for (var wp = 0; getprop(rm_route~ "route/wp[" ~ wp ~ "]/id") != nil; wp += 1) {
		
			setprop(active_rte~ "route/wp[" ~ wp ~ "]/wp-id", getprop(rm_route~ "route/wp[" ~ wp ~ "]/id"));
			
			var alt = getprop(rm_route~ "route/wp[" ~ wp ~ "]/altitude-ft");
			
			var spd = getprop(rm_route~ "route/wp[" ~ wp ~ "]/ias-mach");
			
			if (alt != nil)
				setprop(active_rte~ "route/wp[" ~ wp ~ "]/altitude-ft", alt);
				
			if (spd != nil)
				setprop(active_rte~ "route/wp[" ~ wp ~ "]/ias-mach", spd);
				
		
		}
		
		setprop("/instrumentation/mcdu/input", "MSG: F-PLN SAVED TO ACTIVE RTE");
	
	},
	get_flightplan_id: func(){
		var current_fp = getprop(f_pln_disp~ "current-flightplan");
		if(current_fp == nil or current_fp == ''){
			current_fp = 'current';
		}
		return current_fp;
	},
	get_current_flightplan: func(){
		var current_fp = me.get_flightplan_id();
		me.route_manager.update();
		return me.route_manager.getFlightPlan(current_fp);
	},
	first_displayed_wp: func(){
		#me.update_flightplan_waypoints();
		var first = getprop(f_pln_disp~ "first") or 0;
		me.get_wp(first);
	},
	get_wp: func(idx){
		var wpts = me['waypoints'];
		if(wpts == nil) return nil;
		if(idx >= size(wpts)) return nil;
		var wp = wpts[idx];
		if(typeof(wp) == 'scalar' and wp == '---') return nil;
		return wp;
	},
	insert_procedure_wp: func(type, proc_wp, idx){
		var fp = me.get_current_flightplan();
		var lat = num(string.trim(proc_wp.wp_lat));
		var lon = num(string.trim(proc_wp.wp_lon));
		if( (lat == 0 and lon == 0) or 
			(math.abs(lat) > 90) or 
			(math.abs(lon) > 180) or 
			(proc_wp.wp_type == 'Intc') or 
			(proc_wp.wp_type == 'Hold') ) {
				return nil;
			}
		var wp_pos = {
			lat: lat,
			lon: lon
		};
		var wpt = createWP(wp_pos, proc_wp.wp_name, type);
		#wpt.wp_role = 'sid';
		print('Insert '~type~' WP '~proc_wp.wp_name ~ ' at ' ~ idx);
		fp.insertWP(wpt, idx);
		wpt = fp.getWP(idx);
		if(proc_wp.alt_cstr_ind)
			wpt.setAltitude(proc_wp.alt_cstr, 'at');
		if(proc_wp.spd_cstr_ind)
			wpt.setSpeed(proc_wp.spd_cstr, 'at');
		var fly_type = string.lc(string.trim(proc_wp.fly_type));
		if(fly_type == 'fly-over'){
			wpt.fly_type = 'flyOver';
		}
		return wpt;
	},
	get_destination_wp: func(){
		var f= me.get_current_flightplan(); 
		var current_fp = getprop(f_pln_disp~ "current-flightplan");
		if(current_fp == nil or current_fp == ''){
			current_fp = 'current';
		}
		var numwp = f.getPlanSize();
		var lastidx = numwp - 1;
		var wp_info = nil;
		fmgc.RouteManager.update(current_fp);
		var wp = fmgc.RouteManager.getDestinationWP(current_fp);
		if(wp != nil){
			wp_info = wp;
		}
		return wp_info;
	},
	get_destination_airport: func(){
		var f= me.get_current_flightplan();
		return f.destination;
	},
	update_flightplan_waypoints: func(){
		if(me.updating_wpts) return;
		me.updating_wpts = 1; 
		var first = getprop(f_pln_disp~ "first");
		if(first == nil or first == '') first = 0;
		var current_fp = getprop(f_pln_disp~ "current-flightplan");
		if(current_fp == nil or current_fp == ''){
			current_fp = 'current';
		}
		var fp = me.route_manager.getFlightPlan(current_fp);
		var fpsize = fp.getPlanSize();
		var wpts = [];
		var cur_wp = nil;
		if(current_fp == 'current')
			cur_wp = fp.getWP();
		me.to_wpt_idx = -1;
		me.from_wpt_idx = -1;
		me.to_wpt_line = -1;
		me.from_wpt_line = -1;
		for(var i = 0; i < fpsize; i += 1){
			var wp = fp.getWP(i);
			var real_idx = size(wpts);
			append(wpts, wp);
			var wp_id = wp.id;
			if(cur_wp != nil and cur_wp.id == wp_id){
				me.to_wpt_idx = real_idx;
				me.from_wpt_idx = real_idx - 1;
				me.to_wpt_line = me.to_wpt_idx - first;
				me.from_wpt_line = me.from_wpt_idx - first;
			}
			if(me.route_manager.hasDiscontinuity(wp_id, current_fp))
				append(wpts, '---');
		}
		me.waypoints = wpts;
		me.updating_wpts = 0;
	},
	update_disp : func {
	
		# This function is simply to update the display in the Active Flight Plan Page. This gets first wp ID and then places the others accordingly.
		
		me.update_flightplan_waypoints();
		
		var first = getprop(f_pln_disp~ "first");
		var current_fp = getprop(f_pln_disp~ "current-flightplan");
		if(current_fp == nil or current_fp == ''){
			current_fp = 'current';
		}
		var fp = me.route_manager.getFlightPlan(current_fp);
		var fpsize = fp.getPlanSize();
		var fp_tree = rm_route~ "flightplan/"~current_fp~"/route/";
		
		var hold = getprop("/flight-management/hold/wp_id") or 0;
		
		# Calculate times
		
		for (var wp = 1; wp < fpsize; wp += 1) {
			
			var waypoint = fp.getWP(wp);
		
			var dist = waypoint.leg_distance;
			
			var spd = waypoint.speed_cstr;
			
			var alt = waypoint.alt_cstr;
			
			var gs_min = 0; # Ground Speed in NM/min
			
			if ((spd == nil) or (spd == 0)) {
			
				# Use 250 kts if under FL100 and 0.78 mach if over FL100
				
				if (alt <= 10000)
					spd = 250;
				else
					spd = 0.78;
			
			}
			
			# MACH SPEED
			
			if (spd < 1) {
			
				gs_min = 10 * spd;
			
			}
			
			# AIRSPEED
			
			else {
			
				gs_min = spd + (alt / 200);
			
			}
			
			# Time in Minutes (rounded)
			
			var time_min = int(dist / gs_min);
			
			var last_time = getprop(fp_tree~ "wp[" ~ (wp - 1) ~ "]/leg-time") or 0;
			
			if (wp == 1)
				last_time = last_time + 30;
			# Atm, using 30 min for taxi time. You will be able to change this in INIT B when it's completed
			
			var total_time = last_time + time_min;
			
			setprop(fp_tree~ "wp[" ~ wp ~ "]/leg-time", total_time);
		
		}
		
		# Destination details --------------------------------------------------
		
		var cur_tpy = (current_fp == 'current' or current_fp == 'temporary');
		
		if (fpsize >= 2) {
			me.route_manager.update(current_fp);
			var destWP = me.route_manager.getDestinationWP(current_fp);
			var dest_id = fpsize - 1;
			if(destWP == nil) destWP = fp.getWP(dest_id);
			if(destWP != nil) dest_id = destWP.index;
			#var destWP = fp.getWP(dest_id);
		
			var dest_name = destWP.wp_name;
		
			var dest_time = getprop(fp_tree~ "wp[" ~ dest_id ~ "]/leg-time");

			var dest_time_str = "";
		
			if (dest_time != nil) {
			
				if (dest_time < 10)
					dest_time_str = "000" ~ int(dest_time);
				elsif (dest_time < 100)
					dest_time_str = "00" ~ int(dest_time);
				elsif (dest_time < 1000)
					dest_time_str = "0" ~ int(dest_time);
				else
					dest_time_str = int(dest_time);
			
			} else {
			
				dest_time_str = "----";
			
			}
		
			if(0){
				# Set Airborne to get distance to last waypoint
				var old_actv = getprop(rm_route~ "active");

				setprop(rm_route~ "active", 1);

				setprop(rm_route~ "airborne", 1);

				var rte_dist = getprop(rm_route~ "wp-last/dist");

				setprop(rm_route~ "active", old_actv);
			}
			
			var rte_dist = me.route_manager.getDistance(current_fp, 1);
	
			setprop(f_pln_disp~ "dest", dest_name);
		
			setprop(f_pln_disp~ "time", dest_time_str);
		
			if (rte_dist != nil and rte_dist != 0)
				setprop(f_pln_disp~ "dist", int(rte_dist));
			else
				setprop(f_pln_disp~ "dist", "----");
			
		} else {
		
			setprop(f_pln_disp~ "dest", "----");
			
			setprop(f_pln_disp~ "time", "----");
			
			setprop(f_pln_disp~ "dist", "----");
		
		}
		
		var show_hold = 0;
		
		var wpsize = size(me.waypoints);
		for (var l = 1; l <= 5; l += 1) {
			var wp = first - 1 + l;
			var line_id = 'l'~l;
			if(wp == wpsize){
				setprop(f_pln_disp~ line_id~ "/id", "-----------    END OF F-PLN    -----------");
				setprop(f_pln_disp~ line_id~ "/time", '');
				setprop(f_pln_disp~ line_id~ "/spd_alt", '');
				setprop(f_pln_disp~ line_id~ "/end-marker", 1);
				setprop(f_pln_disp~ line_id~ "/discontinuity-marker", 0);
				setprop(f_pln_disp~ line_id~ "/ovfly", '');
				setprop(f_pln_disp~ line_id~ "/from-wpt", 0);
				setprop(f_pln_disp~ line_id~ "/to-wpt", 0);
				setprop(f_pln_disp~ line_id~ "/missed", 0);
				setprop(f_pln_disp~ line_id~ "/wp-index", -1);
			}
			elsif(wp > wpsize){
				setprop(f_pln_disp~ line_id~ "/id", "");
				setprop(f_pln_disp~ line_id~ "/time", '');
				setprop(f_pln_disp~ line_id~ "/spd_alt", '');
				setprop(f_pln_disp~ line_id~ "/end-marker", 0);
				setprop(f_pln_disp~ line_id~ "/discontinuity-marker", 0);
				setprop(f_pln_disp~ line_id~ "/ovfly", '');
				setprop(f_pln_disp~ line_id~ "/from-wpt", 0);
				setprop(f_pln_disp~ line_id~ "/to-wpt", 0);
				setprop(f_pln_disp~ line_id~ "/missed", 0);
				setprop(f_pln_disp~ line_id~ "/wp-index", -1);
			} else {
				var fp_wp = me.waypoints[wp];
				if(typeof(fp_wp) == 'scalar' and fp_wp == '---'){
					setprop(f_pln_disp~ line_id~ "/id", "-------    F-PLN DISCONTINUITY    -------");
					setprop(f_pln_disp~ line_id~ "/time", '');
					setprop(f_pln_disp~ line_id~ "/spd_alt", '');
					setprop(f_pln_disp~ line_id~ "/end-marker", 0);
					setprop(f_pln_disp~ line_id~ "/discontinuity-marker", 1);
					setprop(f_pln_disp~ line_id~ "/from-wpt", 0);
					setprop(f_pln_disp~ line_id~ "/to-wpt", 0);
					setprop(f_pln_disp~ line_id~ "/missed", 0);
					setprop(f_pln_disp~ line_id~ "/wp-index", -1);
				} else {
					var id = fp_wp.id;
					var fly_type = fp_wp.fly_type;
					setprop(f_pln_disp~ line_id~ "/id", id);
					var ovfly_sym = (fly_type == 'flyOver' ? 'D' : '');
					setprop(f_pln_disp~ line_id~ "/ovfly", ovfly_sym);
					setprop(f_pln_disp~ line_id~ "/wp-index", fp_wp.index);

					var time_min = int(getprop(fp_tree~ "wp[" ~ fp_wp.index ~ "]/leg-time") or 0);

					# Change time to string with 4 characters

					if (time_min < 10)
						setprop(f_pln_disp~ line_id~ "/time", "000" ~ time_min);
					elsif (time_min < 100)
						setprop(f_pln_disp~ line_id~ "/time", "00" ~ time_min);
					elsif (time_min < 100)
						setprop(f_pln_disp~ line_id~ "/time", "0" ~ time_min);
					else
						setprop(f_pln_disp~ line_id~ "/time", time_min);

					var spd = fp_wp.speed_cstr;

					var alt = fp_wp.alt_cstr;

					var spd_str = "";

					var alt_str = "";

					# Check if speed is IAS or mach, if Mach, display M.xx

					if (spd == nil)
						spd = 0;

					if (spd == 0)
						spd_str = "---";
					elsif (spd < 1)
						spd_str = "M." ~ (100 * spd);
					else
						spd_str = spd;

					# Check if Alt is in 1000s or FL

					if (alt == nil)
						alt = 0;

					if (alt == 0)
						alt_str = "----";
					elsif (alt > 9999)
						alt_str = "FL" ~ int(alt / 100);
					else
						alt_str = alt;

					setprop(f_pln_disp~ line_id~ "/spd_alt", spd_str ~ "/" ~ alt_str);
					setprop(f_pln_disp~ line_id~ "/end-marker", 0);
					setprop(f_pln_disp~ line_id~ "/discontinuity-marker", 0);
					setprop(f_pln_disp~ line_id~ "/from-wpt", (me.from_wpt_line == l));
					setprop(f_pln_disp~ line_id~ "/to-wpt", (me.to_wpt_line == (l - 1)));
					setprop(f_pln_disp~ line_id~ "/missed", 
							me.route_manager.isMissedApproach(fp_wp, current_fp));
					if(hold and hold == fp_wp.index){
						show_hold = 1;
						setprop("/instrumentation/mcdu/f-pln/hold-id", l - 1);
					}
				}
			}
		}
		
		setprop("/instrumentation/mcdu/f-pln/show-hold", show_hold);
	
	},
	get_wp_at_line: func(line){
		var idx = getprop(f_pln_disp~ "l" ~ line ~ '/wp-index');
		if(idx == nil or idx == '') return nil;
		var wp = nil;
		if(idx >= 0){
			var fp = me.get_current_flightplan();
			wp = fp.getWP(idx);
		}
		return wp;
	},
	set_restriction: func(line, alt, spd){
		#if(spd != nil)
		#	setprop("autopilot/route-manager/route/wp[" ~ (first) ~ "]/ias-mach", spd);
		#if(alt != nil)
		#	setprop("autopilot/route-manager/route/wp[" ~ (first) ~ "]/altitude-ft", alt);
		var wp = me.get_wp_at_line(line);
		if(spd != nil)
			wp.setSpeed(spd, 'at');
		if(alt != nil)
			wp.setAltitude(alt, 'at');
		me.route_manager.trigger(me.route_manager.SIGNAL_FP_EDIT);
	}

};

var toggle_overfly = func(fp, wp_idx){
	if(!getprop('/instrumentation/mcdu/overfly-mode')) return;
	#var fp = flightplan();
	var wp = fp.getWP(wp_idx);
	if(wp != nil){
		var fly_type = wp.fly_type;
		if(fly_type != 'flyOver')
			wp.fly_type = 'flyOver';
		else 
			wp.fly_type = 'flyBy';
	}
	f_pln.update_disp();
	setprop('/instrumentation/mcdu/overfly-mode', 0);
}

setlistener(f_pln_disp~ 'current-flightplan', func(n){
	var cur = n.getValue();
	var rm = fmgc.RouteManager;
	var fp = rm.getFlightPlan(cur);
	var dep = '';
	var arr = '';
	if(fp != nil){
		var dp = fp.departure;
		if(dp != nil) dep = dp.id;
		var dst = fp.destination;
		if(dst != nil) arr = dst.id;
	}
	setprop(f_pln_disp~ 'departure', dep);
	setprop(f_pln_disp~ 'destination', arr);
}, 0, 1);

setlistener('autopilot/route-manager/current-wp', func(){
	var curpage = getprop('instrumentation/mcdu/page');
	if(curpage == 'f-pln'){
		mcdu.f_pln.update_disp();
	}
}, 0, 0);