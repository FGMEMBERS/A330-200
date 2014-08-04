var fmgc = "/flight-management/control/";
var settings = "/flight-management/settings/";
var fcu = "/flight-management/fcu-values/";
var fmgc_val = "/flight-management/fmgc-values/";
var servo = "/servo-control/";
var flight_modes = "/flight-management/flight-modes/";
var lmodes = flight_modes ~ "lateral/";
var vmodes = flight_modes ~ "vertical/";
var athr_modes = flight_modes ~ "athr/";

setprop("/flight-management/text/qnh", "QNH");

setprop(settings~ "gps-accur", "LOW");

setprop("/flight-management/end-flight", 0);
setprop('/instrumentation/texts/pfd-fmgc-empty-box', '       I');

var fmgc_loop = {
    init : func {
        me.UPDATE_INTERVAL = 0.1;
        me.loopid = 0;

        me.current_wp = 0;
    
        me.fixed_thrust = 0;
        me.capture_alt_at = 0;

        setprop("/flight-management/current-wp", me.current_wp);
        setprop("/flight-management/control/qnh-mode", 'inhg');

        # ALT SELECT MODE

        setprop(fmgc~ "alt-sel-mode", "100"); # AVAIL MODES : 100 1000

        # AUTO-THROTTLE

        setprop(fmgc~ "spd-mode", "ias"); # AVAIL MODES : ias mach
        setprop(fmgc~ "spd-ctrl", "man-set"); # AVAIL MODES : --- fmgc man-set

        setprop(fmgc~ "a-thr/ias", 0);
        setprop(fmgc~ "a-thr/mach", 0);

        setprop(fmgc~ "fmgc/ias", 0);
        setprop(fmgc~ "fmgc/mach", 0);

        setprop(fmgc~ "spd-with-pitch", 0);
        setprop('/flight-management/settings/spd-pitch-min', 0);
        setprop('/flight-management/settings/spd-pitch-max', 0);

        # AUTOPILOT (LATERAL)

        setprop(fmgc~ "lat-mode", "hdg"); # AVAIL MODES : hdg nav1
        setprop(fmgc~ "lat-ctrl", "man-set"); # AVAIL MODES : --- fmgc man-set

        # AUTOPILOT (VERTICAL)

        setprop(fmgc~ "ver-mode", "alt"); # AVAIL MODES : alt (vs/fpa) ils
        setprop(fmgc~ "ver-sub", "vs"); # AVAIL MODES : vs fpa
        setprop(fmgc~ "ver-ctrl", "man-set"); # AVAIL MODES : --- fmgc man-set

        # AUTOPILOT (MASTER)

        setprop(fmgc~ "ap1-master", "off");
        setprop(fmgc~ "ap2-master", "off");
        setprop(fmgc~ "a-thrust", "off");

        # Rate/Load Factor Configuration

        setprop(settings~ "pitch-norm", 0.1);
        setprop(settings~ "roll-norm", 0.2);

        # Terminal Procedure

        setprop("/flight-management/procedures/active", "off"); # AVAIL MODES : off sid star iap

        # Set Flight Control Unit Initial Values

        setprop(fcu~ "ias", 250);
        setprop(fcu~ "mach", 0.78);

        setprop(fcu~ "alt", 10000);
        setprop(fcu~ "vs", 1800);
        setprop(fcu~ "fpa", 5);

        setprop(fcu~ "hdg", 0);

        setprop(fmgc_val~ "ias", 250);
        setprop(fmgc_val~ "mach", 0.78);

        # Servo Control Settings

        setprop(servo~ "aileron", 0);
        setprop(servo~ "aileron-nav1", 0);
        setprop(servo~ "target-bank", 0);

        setprop(servo~ "elevator-vs", 0);
        setprop(servo~ "elevator", 0);
        setprop(servo~ "target-pitch", 0);

        setprop(servo~ "fd-aileron", 0);
        setprop(servo~ "fd-aileron-nav1", 0);
        setprop(servo~ "fd-target-bank", 0);

        #setprop(servo~ "fd-elevator-vs", 0);
        #setprop(servo~ "fd-elevator-gs", 0);
        #setprop(servo~ "fd-elevator", 0);
        setprop(servo~ "fd-target-pitch", 0);

        me.vne = getprop('limits/vne');
        me.reset();
    },
    update : func {   	

        var altitude = getprop("/instrumentation/altimeter/indicated-altitude-ft");
        var ias = ias = getprop("/velocities/airspeed-kt");
        var vmode_vs_fps = getprop('/velocities/vertical-speed-fps');
        setprop("/instrumentation/pfd/vs-100", vmode_vs_fps * 0.6);
        #if(vmode_vs_fps > 8 or vmode_vs_fps < -8){
        #    setprop('/flight-management/flch_active', 1);     
        #} else {
        #    setprop('/flight-management/flch_active', 0);     
        #}
        me.altitude = altitude;
        me.ias = ias;
        me.vs_fps = vmode_vs_fps;

        me.phase = me.flight_phase();

        me.get_settings();
        me.get_current_state();
        me.check_flight_modes();

        me.lvlch_check();

        me.knob_sum();

        me.hdg_disp();

        me.fcu_lights();

        setprop("flight-management/procedures/active", procedure.check());

        setprop(fcu~ "alt-100", me.alt_100());
        var flaps = getprop("/controls/flight/flaps");
        var stall_spd = 0;
        if(flaps <= 0.29)
            stall_spd = 150;
        elsif(flaps == 0.596)
            stall_spd = 135;
        elsif(flaps >= 0.74)
            stall_spd = 120;
        setprop(fmgc_val ~ 'stall-speed', stall_spd);
        setprop(fmgc_val ~ 'ind-stall-speed', stall_spd - 125);
        me.flaps = flaps;
        me.stall_spd = stall_spd;

        var top_desc = me.calc_td();
        me.calc_tc();
        var decel_point = me.calc_decel_point();
        me.calc_speed_change();
        me.calc_level_off();
        var plan_mode = getprop("/instrumentation/nd/plan-mode");
        if(plan_mode != nil and plan_mode){
            setprop("/instrumentation/nd/symbols/aircraft/latitude-deg", getprop('position/latitude-deg'));
            setprop("/instrumentation/nd/symbols/aircraft/longitude-deg", getprop('position/longitude-deg'));
            setprop("/instrumentation/nd/symbols/aircraft/true-heading-deg", getprop('orientation/heading-magnetic-deg'));   
        } else {
            setprop("/instrumentation/nd/symbols/aircraft", '');
        }
        var flplan_active = me.flplan_active;	
        if (flplan_active and  !getprop("/flight-management/freq/ils")){
            var dest_airport = getprop("/autopilot/route-manager/destination/airport");
            var dest_rwy = getprop("/autopilot/route-manager/destination/runway");
            if(dest_airport and dest_rwy){
                var apt_info = airportinfo(dest_airport);
                var rwy_ils = apt_info.runways[dest_rwy].ils;
                if(rwy_ils != nil){
                    var frq = rwy_ils.frequency / 100;
                    var crs = rwy_ils.course;
                    var dist = getprop("/autopilot/route-manager/wp-last/dist");
                    if(dist <= 50){
                        var radio = "/flight-management/freq/";
                        setprop("/flight-management/freq/ils", frq);
                        setprop("/flight-management/freq/ils-crs", int(crs));
                        if (getprop(radio~ "ils-mode")) {

                                mcdu.rad_nav.switch_nav1(1);

                        }
                    }
                }
            }
        }

        # SET OFF IF NOT USED

        if (me.lat_ctrl != "fmgc") {

            setprop("/flight-management/hold/init", 0);

        }

        # Turn off rudder control when AP is off

        if ((me.ap1 == "off") and (me.ap2 == "off")) {
            setprop("/autoland/rudder", 0);
            setprop("/autoland/active", 0);
            setprop("/autoland/phase", "disengaged")
        }

        if ((me.spd_ctrl == "off") or (me.a_thr == "off")) {

            setprop(fmgc~ "a-thr/ias", 0);
            setprop(fmgc~ "a-thr/mach", 0);

            setprop(fmgc~ "fmgc/ias", 0);
            setprop(fmgc~ "fmgc/mach", 0);

        }

        if ((me.lat_ctrl == "off") or ((me.ap1 == "off") and (me.ap2 == "off"))) {

            setprop(servo~ "aileron", 0);
            setprop(servo~ "aileron-nav1", 0);
            setprop(servo~ "target-bank", 0);

        }

        if ((me.ver_ctrl == "off") or ((me.ap1 == "off") and (me.ap2 == "off"))) {

            setprop(servo~ "elevator-vs", 0);
            setprop(servo~ "elevator-gs", 0);
            setprop(servo~ "elevator", 0);
            setprop(servo~ "target-pitch", 0);

        }

        # MANUAL SELECT MODE ===================================================

        ## AUTO-THROTTLE -------------------------------------------------------

        if ((me.spd_ctrl == "man-set") and (me.a_thr == "eng")) {

            if (me.spd_mode == "ias") {

                setprop(fmgc~ "a-thr/ias", 1);
                setprop(fmgc~ "a-thr/mach", 0);

                setprop(fmgc~ "fmgc/ias", 0);
                setprop(fmgc~ "fmgc/mach", 0);

            } else {

                setprop(fmgc~ "a-thr/ias", 0);
                setprop(fmgc~ "a-thr/mach", 1);

                setprop(fmgc~ "fmgc/ias", 0);
                setprop(fmgc~ "fmgc/mach", 0);

            }

        }

        var apEngaged = me.ap_engaged;
        var fdEngaged = getprop("flight-management/control/fd");
        me.ap_engaged = apEngaged;
        me.fd_engaged = fdEngaged;
        var vmode = me.active_ver_mode;
        var prfx_v = substr(vmode,0,2);
        var app_phase = (vmode == 'G/S' or vmode == 'LAND' or vmode == 'FLARE');
        var ver_managed = (me.ver_ctrl == 'fmgc' and flplan_active and !me.vsfpa_mode and vmode != 'SRS');
        var vs_fpm = 0;
        if(altitude < 10000)
            vs_fpm = 1800;
        else{
            vs_fpm = 1600;
        }
        if(vmode == 'SRS')
            vs_fpm = 2500;
        #print("FMGC Loop: AP Eng -> " ~ apEngaged);
        if (!fdEngaged) {

            setprop(servo~ "fd-aileron", 0);
            setprop(servo~ "fd-aileron-nav1", 0);
            setprop(servo~ "fd-target-bank", 0);

            #setprop(servo~ "fd-elevator-vs", 0);
            #setprop(servo~ "fd-elevator-gs", 0);
            #setprop(servo~ "fd-elevator", 0);
            setprop(servo~ "fd-target-pitch", 0);

        }
        if(me.fixed_thrust){
            var min = 0;
            var max = 0;
            var thr = 0;
            if(me.true_vertical_phase == 'CLB'){
                min = 0.2;
                max = 15;
                var thr = 0.94;
            } 
            elsif(me.true_vertical_phase == 'DES'){
                min = -15;
                max = -0.2;
                var thr = 0;
            };
            if(apEngaged){
                setprop('/flight-management/settings/spd-pitch-min', min);
                setprop('/flight-management/settings/spd-pitch-max', max);
                setprop(fmgc~ "spd-with-pitch", 1);
            } else {
                setprop(fmgc~ "spd-with-pitch", 0);
                setprop('/flight-management/settings/spd-pitch-min', 0);
                setprop('/flight-management/settings/spd-pitch-max', 0);
            }
            setprop('/controls/engines/engine[0]/throttle', thr);
            setprop('/controls/engines/engine[1]/throttle', thr);
        } else {
            setprop(fmgc~ "spd-with-pitch", 0);
            setprop('/flight-management/settings/spd-pitch-min', 0);
            setprop('/flight-management/settings/spd-pitch-max', 0);
        }
        if (apEngaged or fdEngaged) {

            ## LATERAL CONTROL -----------------------------------------------------

            #if (me.lat_ctrl == "man-set") {

                

            #}
            if (me.active_lat_mode == "HDG") {

                # Find Heading Deflection

                var bug = getprop(fcu~ "hdg");
                #print("HDG: bug -> " ~ bug);

                var bank = -1 * defl(bug, 20);
                #print("HDG: bank -> " ~ bank);

                var deflection = defl(bug, 180);
                #print("HDG: defl -> " ~ deflection);

                if(apEngaged){
                    setprop(servo~  "aileron", 1);
                    setprop(servo~ "aileron-nav1", 0);

                    if (math.abs(deflection) <= 1)
                    setprop(servo~ "target-bank", 0);
                    else
                        setprop(servo~ "target-bank", bank);
                }
                setprop(servo~  "fd-aileron", 1);
                setprop(servo~ "fd-aileron-nav1", 0);
                if (math.abs(deflection) <= 1)
                setprop(servo~ "fd-target-bank", 0);
                else
                    setprop(servo~ "fd-target-bank", bank);

            } elsif (me.active_lat_mode == "LOC") {

                var nav1_error = getprop("/autopilot/internal/nav1-track-error-deg");

                var agl = me.agl;

                var bank = limit(nav1_error, 30);

                if (agl < 100) {

                    bank = 0; # Level the wings for AUTOLAND

                    setprop(servo~ "target-rudder", bank);	

                }


                if(apEngaged){
                    setprop(servo~ "aileron", 0);

                    setprop(servo~ "aileron-nav1", 1); 
                    setprop(servo~ "target-bank", bank);
                }
                setprop(servo~ "fd-aileron", 0);

                setprop(servo~ "fd-aileron-nav1", 1); 	
                setprop(servo~ "fd-target-bank", bank);

            } # else, this is handed over from fcu to fmgc

            ## VERTICAL CONTROL ----------------------------------------------------

            var vs_setting = me.vs_setting;

            var fpa_setting = me.fpa_setting;

            if(app_phase){
                # Main stuff are done on the PIDs

                autoland.phase_check();

                var agl = me.agl;

                # if (agl > 100) {
                if(apEngaged){
                    if (agl > getprop("/autoland/early-descent")) {

                        setprop(servo~ "elevator-gs", 1);

                        setprop(servo~ "elevator-vs", 0);

                    } else {

                        setprop(servo~ "elevator-gs", 0);

                        setprop(servo~ "elevator-vs", 1);

                    }

                    setprop(servo~ "elevator", 0);
                }

                #setprop(servo~ "fd-elevator", 0);

            } else {
                if(!ver_managed){
                    var vs_ref = vs_fpm; 
                    #TODO: FPA standard settings
                    if(prfx_v == 'VS' or prfx_v == 'FP'){
                        vs_ref = vs_setting; 
                    }
                    if (me.ver_sub == "vs") {

                        var target = getprop(fcu~ "alt");

                        var trgt_vs = 0;

                        if (((altitude - target) * vs_ref) > 0) {

                            trgt_vs = limit((target - altitude) * 2, 200);

                        } else {

                            trgt_vs = limit2((target - altitude) * 2, vs_ref);

                        }
                        if(apEngaged){
                            setprop(servo~ "target-vs", trgt_vs / 60);
                            setprop(servo~ "elevator-vs", 1);
                            setprop(servo~ "elevator", 0);
                            setprop(servo~ "elevator-gs", 0);
                        }
                        #setprop(servo~ "fd-elevator-vs", 0);
                        #setprop(servo~ "fd-elevator", 0);
                        #setprop(servo~ "fd-elevator-gs", 0);
                        setprop(servo~ "fd-target-vs", trgt_vs / 60);
                        setprop(servo~ "fd-target-pitch", (trgt_vs / 60) * 0.1);

                    } else {

                        var target_alt = getprop(fcu~ "alt");

                        var trgt_fpa = limit2((target_alt - altitude) * 2, fpa_setting);
                        if(apEngaged){
                            setprop(servo~ "target-pitch", trgt_fpa);

                            setprop(servo~ "elevator-vs", 0);

                            setprop(servo~ "elevator", 1);

                            setprop(servo~ "elevator-gs", 0);
                        }
                        #setprop(servo~ "fd-elevator-vs", 0);

                        #setprop(servo~ "fd-elevator", 1);

                        #setprop(servo~ "fd-elevator-gs", 0);
                        setprop(servo~ "fd-target-pitch", trgt_fpa);
                    }
                }
            }

        } # End of AP1 Master Check

        # FMGC CONTROL MODE ====================================================

        if ((me.spd_ctrl == "fmgc") and (me.a_thr == "eng")) {

            var cur_wp = me.current_wp;
            #var ias = getprop("/velocities/airspeed-kt");

            ## AUTO-THROTTLE -------------------------------------------------------

            var agl = me.agl;

            if (app_phase and (agl < 3000) and 
                (getprop("/flight-management/spd-manager/approach/mode") == "MANAGED (AUTO)")) {

                setprop(fmgc~ "fmgc/ias", 1);
                setprop(fmgc~ "fmgc/mach", 0);

                setprop(fmgc~ "a-thr/ias", 0);
                setprop(fmgc~ "a-thr/mach", 0);
                var spd = getprop(fmgc_val~ "target-spd");

                if (spd != nil) {
                    if (spd > 1) {
                        setprop("instrumentation/pfd/target-spd", spd);
                    }
                }

            } else {
                if(vmode == 'SRS' and me.srs_spd > 0){
                    var spd = me.srs_spd;
                    setprop(fmgc_val~ "target-spd", spd);
                }
                elsif (((getprop("/flight-management/phase") == "CLB") and (getprop("/flight-management/spd-manager/climb/mode") == "MANAGED (F-PLN)")) or ((getprop("/flight-management/phase") == "CRZ") and (getprop("/flight-management/spd-manager/cruise/mode") == "MANAGED (F-PLN)")) or ((getprop("/flight-management/phase") == "DES") and (getprop("/flight-management/spd-manager/descent/mode") == "MANAGED (F-PLN)")) and (!app_phase) and flplan_active) {

                    var spd = nil;
                    if(getprop("/autopilot/route-manager/route/num") > 0)
                        spd = getprop("/autopilot/route-manager/route/wp[" ~ cur_wp ~ "]/ias-mach");

                    if (spd == nil or spd == 0) {
                        var remaining = me.remaining_nm;
                        if(remaining < decel_point){
                            spd = 180;
                        } else {
                            if (altitude <= 10000){
                                spd = 250;
                            }
                            else{
                                if(vmode_vs_fps <= -8 or me.phase == 'DES'){ #TODO: this fails with new fixed-thrust DES, use true ver mode instead
                                    spd = 280; 
                                } else{
                                    if(altitude < 25000)
                                        spd = 320;
                                    else
                                        spd = 0.78;
                                }
                            }
                        }

                    }
                    if(ias >= (me.vne - 20))
                        spd = me.vne - 20;

                    setprop(fmgc_val~ "target-spd", spd);

                }

                # Performance and Automatic Calculated speeds from the PERF page on the mCDU are managed separately

                manage_speeds();

                setprop(fmgc~ "a-thr/ias", 0);
                setprop(fmgc~ "a-thr/mach", 0);

                var spd = getprop(fmgc_val~ "target-spd");

                if (spd == nil) {
                        
                    if (altitude <= 10000)
                        spd = 250;
                    elsif(altitude < 25000)
                        spd = 320;
                    else
                        spd = 0.78;

                }
                if(ias >= (me.vne - 20))
                    spd = me.vne - 30;

                if (spd < 1) {
                    #TODO: change SPEED/MACH indication on PFD
                    setprop(fmgc~ "fmgc/ias", 0);
                    setprop(fmgc~ "fmgc/mach", 1);

                } else {

                    setprop(fmgc~ "fmgc/ias", 1);
                    setprop(fmgc~ "fmgc/mach", 0);
                    setprop("instrumentation/pfd/target-spd", spd);
                }

            }

        } else {
            var fcu_ias = getprop(fcu ~ 'ias');
            setprop("instrumentation/pfd/target-spd", fcu_ias);
        }

        var lmode = me.active_lat_mode;
        if (apEngaged or fdEngaged) {

            ## LATERAL CONTROL -----------------------------------------------------

            if (lmode == 'NAV') {

                # If A procedure's NOT being flown, we'll fly the active F-PLN (unless it's a hold pattern)

                if (getprop("/flight-management/procedures/active") == "off") {

                    if (((getprop("/flight-management/hold/wp_id") == getprop("/flight-management/current-wp")) or (getprop("/flight-management/hold/init") == 1)) and (getprop("/flight-management/hold/wp_id") != 0)) {

                        if (getprop("/flight-management/hold/init") != 1) {

                            hold_pattern.init();

                        } else {

                            if (getprop("/flight-management/hold/phase") == 5) {

                                hold_pattern.entry();

                            } else {

                                hold_pattern.transit();

                            }	

                            # Now, fly the actual hold

                            var bug = getprop("/flight-management/hold/fly/course");

                            var bank = -1 * defl(bug, 30);

                            var deflection = defl(bug, 180);

                            if(apEngaged){
                                setprop(servo~  "aileron", 1);
                                setprop(servo~ "aileron-nav1", 0);

                                if (math.abs(deflection) <= 1)
                                    setprop(servo~ "target-bank", 0);
                                else
                                    setprop(servo~ "target-bank", bank);
                            }
                            setprop(servo~  "fd-aileron", 1);
                            setprop(servo~ "fd-aileron-nav1", 0);

                            if (math.abs(deflection) <= 1)
                                setprop(servo~ "fd-target-bank", 0);
                            else
                                setprop(servo~ "fd-target-bank", bank);							

                        }

                    } else {

                        setprop("/flight-management/hold/init", 0);

                        var bug = getprop("/autopilot/internal/true-heading-error-deg");

                        var accuracy = getprop(settings~ "gps-accur");

                        var bank = 0; 

                        if (accuracy == "HIGH")
                            bank = limit(bug, 25);
                        else
                            bank = limit(bug, 15);

                        if(apEngaged){
                            setprop(servo~  "aileron", 1);

                            setprop(servo~ "aileron-nav1", 0);

                            setprop(servo~ "target-bank", bank);
                        }
                        setprop(servo~  "fd-aileron", 1);

                        setprop(servo~ "fd-aileron-nav1", 0);

                        setprop(servo~ "fd-target-bank", bank);
                    }

                    # Else, fly the respective procedures

                } else {

                    if (getprop("/flight-management/procedures/active") == "sid") {

                        procedure.fly_sid();

                        var bug = getprop("/flight-management/procedures/sid/course");

                        var bank = -1 * defl(bug, 25);					

                        if(apEngaged){
                            setprop(servo~  "aileron", 1);

                            setprop(servo~ "aileron-nav1", 0);

                            setprop(servo~ "target-bank", bank);
                        }
                        setprop(servo~  "fd-aileron", 1);

                        setprop(servo~ "fd-aileron-nav1", 0);

                        setprop(servo~ "fd-target-bank", bank);

                    } elsif (getprop("/flight-management/procedures/active") == "star") {

                        procedure.fly_star();

                        var bug = getprop("/flight-management/procedures/star/course");

                        var bank = -1 * defl(bug, 25);	
                        if(apEngaged){

                            setprop(servo~  "aileron", 1);

                            setprop(servo~ "aileron-nav1", 0);

                            setprop(servo~ "target-bank", bank);
                        }
                        setprop(servo~  "fd-aileron", 1);

                        setprop(servo~ "fd-aileron-nav1", 0);

                        setprop(servo~ "fd-target-bank", bank);

                    } else {

                        procedure.fly_iap();

                        var bug = getprop("/flight-management/procedures/iap/course");

                        var bank = -1 * defl(bug, 28);		

                        if(apEngaged){

                            setprop(servo~  "aileron", 1);

                            setprop(servo~ "aileron-nav1", 0);

                            setprop(servo~ "target-bank", bank);
                        }
                        setprop(servo~  "fd-aileron", 1);

                        setprop(servo~ "fd-aileron-nav1", 0);

                        setprop(servo~ "fd-target-bank", bank);
                    }

                }

            }

            ## VERTICAL CONTROL ----------------------------------------------------

            if (ver_managed) {

                var current_wp = me.current_wp;

                var target_alt = getprop("/autopilot/route-manager/route/wp[" ~ current_wp ~ "]/altitude-ft");

                #var ref_altitude = altitude;
                var cruise_alt = getprop("autopilot/route-manager/cruise/altitude-ft");
                var destination_elevation = getprop("/autopilot/route-manager/destination/field-elevation-ft");
                var remaining = me.remaining_nm;
                var phase = '';
                var no_constraint = 0;
                var fcu_alt = me.fcu_alt;
                if(remaining <= top_desc){
                    #ref_altitude = destination_elevation; 
                    phase = 'des';
                    setprop("/flight-management/phase", "DES");
                } else {
                    #ref_altitude = cruise_alt;
                    phase = 'clb';
                }
                setprop(fmgc_val ~ 'vnav-phase', phase);

                if (target_alt == nil or target_alt < 0){
                    target_alt = fcu_alt;
                    no_constraint = 1;
                } else {
                    if((vmode == 'CLB' and fcu_alt < target_alt) or 
                       (vmode == 'DES' and fcu_alt > target_alt)){
                        target_alt = fcu_alt;
                        no_constraint = 1;
                    }   
                }
                setprop(fmgc_val ~ 'vnav-target-alt', target_alt);

                var alt_diff = target_alt - altitude;

                var final_vs = 0;
                var abs_diff = math.abs(alt_diff);

                if (abs_diff >= 500) {
                    if(no_constraint == 0){
                        var ground_speed_kt = getprop("/velocities/groundspeed-kt");

                        #var leg_dist_nm = getprop("/instrumentation/gps/wp/leg-distance-nm");
                        var leg_dist_nm = getprop("/autopilot/route-manager/wp/dist");
                        #if(no_constraint == 1)
                        #    leg_dist_nm = remaining;

                        #var leg_time_hr = leg_dist_nm / ground_speed_kt;

                        #var leg_time_sec = leg_time_hr * 3600;

                        #var target_fps = (alt_diff / leg_time_sec) + 5;
                        var nm_min = ground_speed_kt / 60.0;
                        var min = leg_dist_nm / nm_min;
                        if(min == 0) {
                            final_vs = 0;
                        }
                        else{
                            final_vs = alt_diff / min;
                            final_vs = final_vs / 60.0;
                        }
                        final_vs = limit(final_vs, 40);
                    } else {
                        #TODO: review calculated V/S
                        var vs_fpm = 0;
                        if(target_alt > altitude){
                            if(altitude < 10000)
                                vs_fpm = 1800;
                            else{
                                vs_fpm = 1600;
                            }
                        } else {
                            vs_fpm = -2400;
                        }
                        final_vs = limit(vs_fpm / 60.0, 40);
                    }
                } else {
                        if (((altitude - target_alt) * vs_setting) > 0) {
                            final_vs = limit((target_alt - altitude) * 2, 200);
                        } else {
                            final_vs = limit2((target_alt - altitude) * 2, vs_setting);
                        } 
                        final_vs = final_vs / 60.0;
                }
                setprop(fmgc_val ~ 'vnav-final-vs', final_vs);
                if(apEngaged){
                    setprop(servo~ "target-vs", final_vs);

                    setprop(servo~ "elevator-vs", 1);

                    setprop(servo~ "elevator", 0);

                    setprop(servo~ "elevator-gs", 0);
                }
                setprop(servo~ "fd-target-vs", final_vs);
                setprop(servo~ "fd-target-pitch", final_vs * 0.1);
            }

        } # End of AP1 MASTER CHECK

    },
    get_settings : func {

        me.spd_mode = getprop(fmgc~ "spd-mode");
        me.spd_ctrl = getprop(fmgc~ "spd-ctrl");

        me.lat_mode = getprop(fmgc~ "lat-mode");
        me.lat_ctrl = getprop(fmgc~ "lat-ctrl");

        me.ver_mode = getprop(fmgc~ "ver-mode");
        me.ver_ctrl = getprop(fmgc~ "ver-ctrl");

        me.ver_sub = getprop(fmgc~ "ver-sub");

        me.ap1 = getprop(fmgc~ "ap1-master");
        me.ap2 = getprop(fmgc~ "ap2-master");
        me.a_thr = getprop(fmgc~ "a-thrust");
        
        me.vs_setting = getprop(fcu~ "vs");

        me.fpa_setting = getprop(fcu~ "fpa");
        me.crz_fl = getprop("/flight-management/crz_fl");
        me.fcu_alt = getprop(fcu~'alt');
        me.v2_spd = getprop('/instrumentation/fmc/vspeeds/V2');
        me.vsfpa_mode = getprop(fmgc~'vsfpa-mode');

    },
    get_current_state : func(){
        me.flplan_active = getprop("/autopilot/route-manager/active");
        me.agl = getprop("/position/altitude-agl-ft");
        me.current_wp = getprop("autopilot/route-manager/current-wp");
        me.remaining_nm = getprop("autopilot/route-manager/distance-remaining-nm");
        me.airborne = !getprop("/gear/gear[3]/wow");
        me.nav_in_range = getprop('instrumentation/nav/in-range');
        me.gs_in_range = getprop('instrumentation/nav/gs-in-range');
        me.autoland_phase = getprop('/autoland/phase');
        me.vs_fpm = int(0.6 * me.vs_fps) * 100;
        me.ap_engaged = ((me.ap1 == "eng") or (me.ap2 == "eng"));
    },
    check_flight_modes : func{
        var flplan_active = me.flplan_active;
        me.active_athr_mode = '';
        me.armed_athr_mode = '';
        me.active_lat_mode = '';
        me.armed_lat_mode = '';
        me.active_ver_mode = '';
        me.armed_ver_mode = '';
        me.accel_alt = 1500;
        me.srs_spd = 0;
        if(me.v2_spd > 0)
            me.srs_spd = me.v2_spd + 10; 
        
        # Basic Lateral Mode
        var lmode = '';
        var lat_sel_mode = 'HDG';#TODO: support track mode
        if (me.lat_ctrl == "man-set") {
            if (me.lat_mode == "hdg") {
                lmode = lat_sel_mode;            
            } 
            elsif(me.lat_mode == "nav1"){
                lmode = 'LOC';
            }
        }
        #TODO: support ROLLOUT lat mode
        elsif(me.lat_ctrl == "fmgc"){
            lmode = 'NAV';
        }
        
        #Basic Vertical Mode
        var vmode = '';
        var fcu_alt = me.fcu_alt;
        var vs_fpm = me.vs_fpm;
        var raw_alt_diff = fcu_alt - me.altitude;
        var alt_diff = math.abs(raw_alt_diff);
        var phase = me.phase;
        var vphase = '';
        var vmode_main = '';
        var crz_alt = me.crz_fl * 100;
        me.true_vertical_phase = '';
        if(raw_alt_diff > 0)
            me.true_vertical_phase = 'CLB';
        elsif(raw_alt_diff < 0)
            me.true_vertical_phase = 'DES';
        if(phase == 'CLB' or phase == 'DES')
            vphase = phase;
        elsif(phase == 'T/O')
            vphase = 'CLB';
        elsif(phase == 'APP')
            vphase = 'DES';
        
        if(alt_diff <= 100){
            vmode_main = 'ALT';
            me.capture_alt_at = 0;
        } else {
            if(phase == 'CRZ'){
                if((crz_alt - fcu_alt) > 10)
                    vmode_main = 'DES';
                else
                    vmode_main = 'ALT*';
            }
            else{
                var capture_alt_at = me.capture_alt_at;
                if(capture_alt_at == 0)
                    capture_alt_at = (vs_fpm != 0 ? fcu_alt - (vs_fpm / 2) : fcu_alt);
                var capture_alt_rng = math.abs(fcu_alt - capture_alt_at);
                if(alt_diff < capture_alt_rng){
                    vmode_main = 'ALT*';
                    me.capture_alt_at = capture_alt_at;
                } else {
                    vmode_main = vphase;
                }
            }  
        }
        
        if(me.ver_ctrl == "man-set" or !flplan_active){
            if(me.ver_mode == 'alt'){
                vmode = vmode_main;
                if(vmode == vphase){
                    if(me.vsfpa_mode){
                        var sub = me.ver_sub;
                        if(sub == 'vs'){
                            vmode = 'VS '~me.vs_setting;
                        } else {
                            vmode = 'FPA '~me.fpa_setting;
                        }
                    } 
                    else {
                        if(raw_alt_diff < -10)
                            vmode = 'DES';
                        vmode = 'OP '~vmode;
                    } 
                }
            }
            elsif(me.ver_mode = 'ils'){
                vmode = 'G/S';
            }
        }
        elsif(me.ver_ctrl == "fmgc"){
            vmode = vmode_main;
        }
        
        if(!me.airborne){
            me.active_athr_mode = 'MAN';
            me.armed_athr_mode = 'TO';
            me.active_lat_mode = ''; #TODO: support RWY
            me.armed_lat_mode = lmode;
            if(me.autoland_phase == 'rollout')
                me.active_ver_mode = 'ROLLOUT';
            else 
                me.active_ver_mode = '';
            me.armed_ver_mode = vmode;
        } else {
            
            #LATERAL
            
            if(me.agl > 30){
                if(lmode == 'LOC'){
                    if(me.nav_in_range){
                        me.active_lat_mode = lmode;
                        me.armed_lat_mode = 'ROLLOUT';
                    } else {
                        me.active_lat_mode = lat_sel_mode;
                        me.armed_lat_mode = lmode;
                    }
                }
                elsif(lmode == 'NAV'){
                    if(flplan_active){
                        me.active_lat_mode = lmode;
                        me.armed_lat_mode = '';
                    } else {
                        me.active_lat_mode = lat_sel_mode;
                        me.armed_lat_mode = lmode;
                    }
                } else {
                    me.active_lat_mode = lmode;
                    me.armed_lat_mode = '';
                }
            } else {
                me.active_lat_mode = '';  #TODO: support RWY TRK
                me.armed_lat_mode = lmode;
            }
            
            #VERTICAL
            
            if(me.agl < 1500 and me.srs_spd > 0 and me.phase == 'CLB'){
                me.active_ver_mode = 'SRS';
                me.armed_ver_mode = vmode;
            } else {
                if(vmode == 'G/S'){
                    if(me.gs_in_range){
                        var flare = (me.autoland_phase == 'flare');
                        var below_early_des = (me.agl < getprop('autoland/early-descent'));
                        if(flare){
                            me.active_ver_mode = 'FLARE';
                            me.armed_ver_mode = '';
                        }
                        elsif(below_early_des){
                            me.active_ver_mode = 'LAND';
                            me.armed_ver_mode = 'FLARE';
                        } else {
                            me.active_ver_mode = vmode;
                            me.armed_ver_mode = 'LAND'; 
                        }
                    } else {
                        me.active_ver_mode = vmode_main;
                        me.armed_ver_mode = vmode;
                    }
                } else {
                    if(vmode == 'ALT'){
                        me.active_ver_mode = vmode;
                        me.armed_ver_mode = '';
                    } else {
                        me.active_ver_mode = vmode;
                        me.armed_ver_mode = 'ALT'; 
                    }
                }
            }
            
            #ATHR 
            var fixed_thrust = 0;
            if(me.a_thr == 'eng'){
                var spd_mode = '';
                if(me.spd_mode == "ias"){
                    spd_mode = 'SPEED';
                } else {
                    spd_mode = 'MACH';
                }
                if(!me.ap_engaged){
                    me.active_athr_mode = spd_mode;
                } else {
                    me.active_athr_mode = me.get_athr_mode(me.active_ver_mode, spd_mode);
                    me.armed_athr_mode = me.get_athr_mode(me.armed_ver_mode, spd_mode);
                    if(me.active_athr_mode == me.armed_athr_mode)
                        me.armed_athr_mode = '';
                    if(me.active_athr_mode != spd_mode)
                        fixed_thrust = 1;
                }
            } else {
                me.active_athr_mode = 'MAN';
                me.armed_athr_mode = '';
            }
            me.fixed_thrust = fixed_thrust;
        }
        setprop(athr_modes~'active', me.active_athr_mode);
        setprop(athr_modes~'armed', me.armed_athr_mode);
        setprop(vmodes~'active', me.active_ver_mode);
        setprop(vmodes~'armed', me.armed_ver_mode);
        setprop(lmodes~'active', me.active_lat_mode);
        setprop(lmodes~'armed', me.armed_lat_mode);
        #setprop(fmgc ~'fixed-thrust', fixed_thrust);
        
    },
    get_athr_mode: func(vmode, spd_mode){
        if(vmode == 'SRS' or 
           vmode == 'CLB' or 
           vmode == 'DES' or 
           vmode == 'OP CLB' or 
           vmode == 'OP DES'
          ){
            var thr_mode = 'THR';
            var vphase = me.true_vertical_phase;
            if(vphase == 'CLB')
                thr_mode = thr_mode~ ' CLB';
            else 
                thr_mode = thr_mode~ ' IDLE';
            return thr_mode;
        }
        return spd_mode;
    },
    lvlch_check : func {

        if ((me.ap1 == "eng") or (me.ap2 == "eng")) {

            var vs_fps = me.vs_fps;

            if (math.abs(vs_fps) > 8)
                setprop("/flight-management/fcu/level_ch", 1);
            else
                setprop("/flight-management/fcu/level_ch", 0);

        } else
            setprop("/flight-management/fcu/level_ch", 0);

    },

    knob_sum : func {

        var ias = getprop(fcu~ "ias");

        var mach = getprop(fcu~ "mach");

        setprop(fcu~ "spd-knob", ias + (100 * mach));

        var vs = getprop(fcu~ "vs");

        var fpa = getprop(fcu~ "fpa");

        setprop(fcu~ "vs-knob", fpa + (vs/100));

    },
    hdg_disp : func {

        var hdg = getprop(fcu~ "hdg");

        if (hdg < 10)
            setprop(fcu~ "hdg-disp", "00" ~ hdg);
        elsif (hdg < 100)
            setprop(fcu~ "hdg-disp", "0" ~ hdg);
        else
            setprop(fcu~ "hdg-disp", "" ~ hdg);

    },

    fcu_lights : func {

        if (me.lat_mode == "nav1")
            setprop(fmgc~ "fcu/nav1", 1);
        else
            setprop(fmgc~ "fcu/nav1", 0);

        if (me.ver_mode == "ils")
            setprop(fmgc~ "fcu/ils", 1);
        else
            setprop(fmgc~ "fcu/ils", 0);

        if (me.a_thr == "eng")
            setprop(fmgc~ "fcu/a-thrust", 1);
        else
            setprop(fmgc~ "fcu/a-thrust", 0);

        if (me.ap1 == "eng")
            setprop(fmgc~ "fcu/ap1", 1);
        else
            setprop(fmgc~ "fcu/ap1", 0);

        if (me.ap2 == "eng")
            setprop(fmgc~ "fcu/ap2", 1);
        else
            setprop(fmgc~ "fcu/ap2", 0);

    },

    alt_100 : func {

        var alt = me.altitude;

        return int(alt/100);

    },

    flight_phase : func {

        var phase = getprop("/flight-management/phase");
        var ias = me.ias;

        if ((phase == "T/O") and (!getprop("/gear/gear[3]/wow") and ias > 80)) {

            setprop("/flight-management/phase", "CLB");

        } elsif (phase == "CLB") {

            var crz_fl = me.crz_fl;

            if (crz_fl != 0) {

                if (getprop("/position/altitude-ft") >= ((crz_fl * 100) - 500))
                    setprop("/flight-management/phase", "CRZ");

            } else {

                if (getprop("/position/altitude-ft") > 26000)
                    setprop("/flight-management/phase", "CRZ");

            }

        } elsif (phase == "CRZ") {

            var crz_fl = getprop("/flight-management/crz_fl");

            if (crz_fl != 0) {

                if (getprop("/position/altitude-ft") < ((crz_fl * 100) - 500))
                    setprop("/flight-management/phase", "DES");

            } else {

                if (getprop("/position/altitude-ft") < 26000)
                    setprop("/flight-management/phase", "DES");

            }

        } elsif ((phase == "DES") and (getprop("/flight-management/control/ver-mode") == "ils")) {

            setprop("/flight-management/phase", "APP");
            setprop('/instrumentation/efis/nd/app-mode', 'ILS APP');

        } elsif ((phase == "APP") and (getprop("/gear/gear/wow"))) {

            setprop("/flight-management/phase", "T/O");
            setprop('/instrumentation/efis/nd/app-mode', '');

            new_flight();

            me.current_wp = 0;

        }
        return getprop("/flight-management/phase");
    },
    calc_td: func {
        var tdNode = "/autopilot/route-manager/vnav/td";
        var top_of_descent = 36;

        if (getprop("/autopilot/route-manager/active")){
            var cruise_alt = getprop("autopilot/route-manager/cruise/altitude-ft");
            var destination_elevation = getprop("/autopilot/route-manager/destination/field-elevation-ft");
            if(cruise_alt > 10000) {
                top_of_descent += 21;
                if(cruise_alt > 29000)
                {
                    top_of_descent += 41.8;
                    if(cruise_alt > 36000)
                    {
                        top_of_descent += 28;
                        top_of_descent += (cruise_alt - 36000) / 1000 * 3.8;
                    }
                    else
                    {
                        top_of_descent += (cruise_alt - 29000) / 1000 * 4;
                    }
                }
                else
                {
                    top_of_descent += (cruise_alt - 10000) / 1000 * 2.2;
                }
                top_of_descent += 6.7;
            } else {
                top_of_descent += (cruise_alt - 3000) / 1000 * 3;
            }
            top_of_descent -= (destination_elevation / 1000 * 3);
            var td_raw_prop = 'instrumentation/efis/nd/current-td';
            var cur_td = getprop(td_raw_prop);
            if(cur_td == nil) cur_td = 0;
            if(math.abs(top_of_descent - cur_td) > 4){
                setprop(td_raw_prop, top_of_descent);
                var bearing = me.calc_point_bearing(top_of_descent, -1);
                setprop(tdNode~'/bearing-deg', bearing);
            }

            #print("TD: " ~ top_of_descent);
            var f= flightplan(); 
            #                   var topClimb = f.pathGeod(0, 100);
            var topDescent = f.pathGeod(-1, -top_of_descent);
            setprop(tdNode ~ "/latitude-deg", topDescent.lat); 
            setprop(tdNode ~ "/longitude-deg", topDescent.lon); 
            if(me.ver_ctrl == "fmgc")
                setprop(tdNode ~ "/vnav-armed", 1);
            else
                setprop(tdNode ~ "/vnav-armed", 0);
        } else {
            var node = props.globals.getNode(tdNode);
            if(node != nil) props.globals.getNode(tdNode).remove(); 
        }
        return top_of_descent;
    },
    calc_tc: func {
        var tcNode = "/autopilot/route-manager/vnav/tc";
        var tc_raw_prop = 'instrumentation/efis/nd/current-tc';
        var phase = me.phase;
        var vspd_fps = me.vs_fps;
        if(vspd_fps == 0) return;
        if (getprop("/autopilot/route-manager/active") and 
            !getprop("/gear/gear[3]/wow") and 
            (phase == 'CLB' or 
             (phase == 'CRZ' and vspd_fps >= -0.8))){
            var vs_fpm = me.vs_fpm;
            if(vs_fpm == 0) return;
            var cruise_alt = getprop("autopilot/route-manager/cruise/altitude-ft");
            var altitude = me.altitude;
            var d = cruise_alt - altitude;
            if(d > 100){
                
                var trans_alt = cruise_alt - (vs_fpm / 2);
                var before_trans_nm = me.nm2level(altitude, trans_alt, vs_fpm);
                #before_trans_nm = before_trans_nm * 2;
                var after_trans_nm = me.nm2level(trans_alt, cruise_alt, vs_fpm / 4);
                #print('ALT: ' ~ altitude);
                #print('D: ' ~ d);
                #print("Trans ALT: "~trans_alt);
                #print("VS: "~vs_fpm);
                #print("Before NM: "~before_trans_nm);
                #print("After NM: "~after_trans_nm);
                #print('---');
                if(before_trans_nm < 1 or 
                   (d <= 500 and before_trans_nm >= 1) or 
                    d < 250) 
                    return;
                #var min = d / vs_fpm;
                #var ground_speed_kt = getprop("/velocities/groundspeed-kt");
                #var nm_min = ground_speed_kt / 60;
                #var nm = nm_min * min;
                var nm = before_trans_nm + after_trans_nm;
                print("NM: "~nm);
                print('-----');
                var remaining = me.remaining_nm;
                var totdist = getprop("autopilot/route-manager/total-distance");
                nm = nm + (totdist - remaining);
                #if(d > 500)
                #    nm += 8;
                #else 
                #    nm += (8 * (d / 500));
                var cur_tc = getprop(tc_raw_prop);
                if(cur_tc == nil) cur_tc = 0;
                if(math.abs(nm - cur_tc) > 0){
                    setprop(tc_raw_prop, nm);
                    #var bearing = me.calc_point_bearing(nm);
                    #setprop(tcNode~'/bearing-deg', bearing);
                } 
                var f= flightplan(); 
                #print("TC: " ~ nm);
                var topClimb = f.pathGeod(0, nm);
                setprop(tcNode ~ "/latitude-deg", topClimb.lat); 
                setprop(tcNode ~ "/longitude-deg", topClimb.lon); 
            } else {
                var node = props.globals.getNode(tcNode);
                if(node != nil) node.remove();
                setprop(tc_raw_prop, 0);
            }
        } else {
            var node = props.globals.getNode(tcNode);
            if(node != nil) node.remove();
            setprop(tc_raw_prop, 0);
        }

    },
    calc_level_off: func {
        var edProp = "/autopilot/route-manager/vnav/ed"; #END OF DESCENT
        var scProp = "/autopilot/route-manager/vnav/sc"; #STEP CLIMB
        var remnode = func(ndpath){
            var node = props.globals.getNode(ndpath);
            if(node != nil) node.remove();
        };
        if (getprop("/autopilot/route-manager/active") and !getprop("/gear/gear[3]/wow")){
            var vs_fpm = me.vs_fpm;
            if(vs_fpm == 0) return;
            var trgt_alt = 0;
            var vnav_actv = 0;
            if(me.ver_ctrl == "fmgc"){
                trgt_alt = getprop(fmgc_val ~ 'vnav-target-alt');
                vnav_actv = 1;
            } else {
                trgt_alt = me.fcu_alt;
            }
            if(trgt_alt == nil){
                remnode(edProp);
                remnode(scProp); 
                setprop('instrumentation/efis/nd/current-sc', 0);
                setprop('instrumentation/efis/nd/current-ed', 0);
                return;
            }
            var altitude = me.altitude;
            var d = 0;
            var prop = '';
            var deact_prop = '';
            var climbing = 0;
            if(altitude > trgt_alt){
                d = altitude - trgt_alt;
                prop = 'ed';
                deact_prop = 'sc';
            } else {
                climbing = 1;
                var cruise_alt = getprop("autopilot/route-manager/cruise/altitude-ft");
                if(cruise_alt == trgt_alt){
                    #print('SAME ALT');
                    remnode(scProp);
                    if(getprop('instrumentation/efis/nd/current-sc') != 0)
                        setprop('instrumentation/efis/nd/current-sc', 0);
                    return;
                }
                d = trgt_alt - altitude;
                prop = 'sc';
                deact_prop = 'ed';
            }
            if(d > 100){
                var min = d / math.abs(vs_fpm);
                var ground_speed_kt = getprop("/velocities/groundspeed-kt");
                var nm_min = ground_speed_kt / 60;
                var nm = nm_min * min;
                var remaining = me.remaining_nm;
                var totdist = getprop("autopilot/route-manager/total-distance");
                nm = nm + (totdist - remaining);
                #if(d > 500)
                #    nm += 8;
                #else 
                #    nm += (8 * (d / 500));
                var node = "/autopilot/route-manager/vnav/" ~ prop;
                var lo_raw_prop = 'instrumentation/efis/nd/current-'~prop;
                var cur_lo = getprop(lo_raw_prop);
                if(cur_lo == nil) cur_lo = 0;
                if(math.abs(nm - cur_lo) > 0.5){
                    setprop(lo_raw_prop, nm);
                    var bearing = me.calc_point_bearing(nm);
                    setprop(node~'/bearing-deg', bearing);
                }

                var f= flightplan(); 
                #print("TC: " ~ nm);
                var point = f.pathGeod(0, nm);

                var deact_node = "/autopilot/route-manager/vnav/" ~ deact_prop;
                setprop(node ~ "/latitude-deg", point.lat); 
                setprop(node ~ "/longitude-deg", point.lon);
                remnode(deact_node); 
            } else {
                remnode(edProp);
                remnode(scProp); 
                if(getprop('instrumentation/efis/nd/current-sc') != 0)
                    setprop('instrumentation/efis/nd/current-sc', 0);
                if(getprop('instrumentation/efis/nd/current-ed') != 0)
                    setprop('instrumentation/efis/nd/current-ed', 0);
            }
        } else {
            remnode(edProp);
            remnode(scProp); 
            if(getprop('instrumentation/efis/nd/current-sc') != 0)
                setprop('instrumentation/efis/nd/current-sc', 0);
            if(getprop('instrumentation/efis/nd/current-ed') != 0)
                setprop('instrumentation/efis/nd/current-ed', 0);
        }

    },
    calc_decel_point: func{
        var decelNode = "/instrumentation/nd/symbols/decel";
        if (getprop("/autopilot/route-manager/active")){
            var actrte = "/autopilot/route-manager/route/";
            var f= flightplan(); 
            var numwp = getprop(actrte~"num");
            var i = 0;
            var first_approach_wp = nil;
            for(i = 0; i < numwp; i = i + 1){
                var wp = f.getWP(i);
                if(wp != nil){
                    var role = wp.wp_role;
                    if(role == 'approach'){
                        first_approach_wp = wp;
                        break;
                    }
                }
            }
            if(first_approach_wp != nil){
                var dist = wp.distance_along_route;
                var totdist = getprop("autopilot/route-manager/total-distance");
                dist = totdist - dist;
                var nm = dist + 11;
                var decelPoint = f.pathGeod(-1, -nm);
                setprop(decelNode ~ "/latitude-deg", decelPoint.lat); 
                setprop(decelNode ~ "/longitude-deg", decelPoint.lon); 
                return nm;
            } else {
                setprop(decelNode, '');
            }
        } else {
            setprop(decelNode, '');
        }
        return 0;
    },
    calc_speed_change: func(){
        var spdChangeNode = "/autopilot/route-manager/spd/spd-change-point";
        var spd_change_raw = 'instrumentation/efis/nd/spd-change-raw';
        if (!getprop("/autopilot/route-manager/active") or getprop("/gear/gear[3]/wow"))
            return 0;
        if ((me.spd_ctrl != "fmgc") or (me.a_thr == "off")) 
            return 0;
        var phase = getprop("/flight-management/phase");
        var trgt_alt = 0;
        if(me.ver_ctrl == "fmgc"){
            if(phase == 'CLB')
                trgt_alt = getprop("autopilot/route-manager/cruise/altitude-ft");
            else
                trgt_alt = getprop(fmgc_val ~ 'vnav-target-alt');
        } else {
            trgt_alt = me.fcu_alt;
        }
        var altitude = me.altitude;
        var vs_fpm = me.vs_fpm;
        if(vs_fpm == 0) return;
        var spd_cange_count = 0;
        foreach(var alt; [10000,14000,25000,26000]){
            var alt_100 = alt / 100;
            var node_path = spdChangeNode ~ '-' ~ alt_100;
            var node_raw_path = spd_change_raw ~ '-' ~ alt_100;
            var cond = 0;
            if(phase == 'CLB'){
                var mode = getprop("/flight-management/spd-manager/climb/mode");
                if((mode == "MANAGED (F-PLN)" and (alt == 14000 or alt == 26000)) or 
                   (mode != "MANAGED (F-PLN)" and (alt == 10000 or alt == 25000)))
                    cond = 0;
                else
                    cond = ((altitude < alt) and trgt_alt >= alt);
            }                                                
            elsif(phase == 'DES'){
                var mode = getprop("/flight-management/spd-manager/descent/mode");
                if((mode == "MANAGED (F-PLN)" and (alt == 14000 or alt == 26000)) or 
                   (mode != "MANAGED (F-PLN)" and (alt == 10000 or alt == 25000)))
                    cond = 0;
                else
                    cond = ((altitude > alt)  and trgt_alt <= alt);
                #print('SPD ALT' ~ alt ~ ' (DES): '~ cond);
            }      
            if(cond){
                var d = 0;
                if(phase == 'CLB')
                    d = alt - altitude;
                elsif(phase == 'DES')
                    d = altitude - alt;
                if(d > 100){
                    var min = d / math.abs(vs_fpm);
                    var ground_speed_kt = getprop("/velocities/groundspeed-kt");
                    var nm_min = ground_speed_kt / 60;
                    var nm = nm_min * min;
                    var remaining = me.remaining_nm;
                    var totdist = getprop("autopilot/route-manager/total-distance");
                    nm = nm + (totdist - remaining);
                    if(d > 500 and alt == trgt_alt)
                        nm += 8;
                    elsif(d <= 500 and alt == trgt_alt)
                        nm += (8 * (d / 500));
                    else 
                        nm += 1;
                    var cur_raw = getprop(node_raw_path);
                    if(cur_raw == nil) cur_raw = 0;
                    if(math.abs(nm - cur_raw) >= 1){
                        setprop(node_raw_path, nm);
                    } 
                    var f= flightplan(); 
                    #print("TC: " ~ nm);
                    var point = f.pathGeod(0, nm);
                    setprop(node_path ~ "/latitude-deg", point.lat); 
                    setprop(node_path ~ "/longitude-deg", point.lon); 
                } else {
                    var node = props.globals.getNode(node_path);
                    if(node != nil) node.remove();
                    setprop(node_raw_path, 0);
                }
            }
        }
    },
    nm2level: func(from_alt, to_alt, vs_fpm){
        if(vs_fpm == 0) return 0;
        var d = to_alt - from_alt;
        var min = d / vs_fpm;
        var ground_speed_kt = getprop("/velocities/groundspeed-kt");
        var nm_min = ground_speed_kt / 60;
        var nm = nm_min * min;
        return nm;
    },
    calc_point_bearing: func(nm, offset = 0){
        var rt = 'autopilot/route-manager/route/';
        var n = getprop(rt~'num');
        if(n == nil or n == 0) return 0;
        var bearing = 0;
        if(offset < 0){
            var totdist = getprop("autopilot/route-manager/total-distance");
            nm = totdist - nm;
        }
        var idx = 0;
        for(idx = 0; idx < n; idx += 1){
            var wp = rt~'wp['~idx~']';
            var dist = getprop(wp~'/distance-along-route-nm');
            if(dist >= nm){
                break;
            }
            bearing = getprop(wp~'/leg-bearing-true-deg');
        }
        return bearing;
    },
    reset : func {
        me.loopid += 1;
        me._loop_(me.loopid);
    },
    _loop_ : func(id) {
        id == me.loopid or return;
        me.update();
        settimer(func { me._loop_(id); }, me.UPDATE_INTERVAL);
    }

};

setlistener("sim/signals/fdm-initialized", func{
    fmgc_loop.init();
    print("Flight Management and Guidance Computer Initialized");
});

setlistener('controls/engines/engine/reverser', func{
    var rev = getprop('controls/engines/engine/reverser');
    var rev_detent = getprop('controls/engines/detents/rev');
    var throttle = getprop('controls/engines/engine[1]/throttle');
    if(rev){
        setprop('controls/engines/detents/throttle', rev_detent - throttle);
        setprop('controls/engines/detents/current', 'rev');
    } else {
        var detent_thr = getprop('controls/engines/detents/throttle');
        setprop('controls/engines/detents/throttle', 0);
        settimer(func{setprop('controls/engines/detents/current', 'none')},0.25);
    }

});

setlistener('/flight-management/control/a-thrust', func{
    var athr = getprop('/flight-management/control/a-thrust');
    var clb_detent = getprop('controls/engines/detents/clb');
    var throttle = getprop('controls/engines/engine[1]/throttle');
    if(athr == 'eng'){
        setprop('controls/engines/detents/throttle', clb_detent - throttle);
        setprop('controls/engines/detents/current', 'clb');
    } else {
        var detent_thr = getprop('controls/engines/detents/throttle');
        setprop('controls/engines/detents/throttle', 0);
        settimer(func{setprop('controls/engines/detents/current', 'none')},0.25);
    }

});

setlistener(athr_modes~'active', func(){
    var mode = athr_modes~'active';
    var box_node = 'instrumentation/pfd/athr-active-box';
    if(mode != ''){
        setprop(box_node, 1);
        settimer(func(){
            setprop(box_node, 0);     
        }, 5);
    } else {
        setprop(box_node, 1);
    }
}, 0, 0);

setlistener(lmodes~'active', func(){
    var mode = lmodes~'active';
    var box_node = 'instrumentation/pfd/lat-active-box';
    if(mode != ''){
        setprop(box_node, 1);
        settimer(func(){
            setprop(box_node, 0);     
        }, 5);
    } else {
        setprop(box_node, 1);
    }
}, 0, 0);

setlistener(vmodes~'active', func(){
    var mode = vmodes~'active';
    var box_node = 'instrumentation/pfd/ver-active-box';
    if(mode != ''){
        setprop(box_node, 1);
        settimer(func(){
            setprop(box_node, 0);     
        }, 5);
    } else {
        setprop(box_node, 1);
    }
}, 0, 0);
