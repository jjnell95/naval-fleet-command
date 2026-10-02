"""Authored operation structure applied by every scenario builder. Idempotent on shipped JSON.

All scheduling, air readiness and magazine budgets are fictional game design, not real plans.
Theatre identity and geometry remain owned by the original geographic scenario builders.

Each operation's events are reactive (scripts/simulation/operation_director.gd reads them): they
fire on the battle itself, such as a convoy passing a point, what a side's own plot holds, a base's
readiness, a ship hit or radiating, and some of their timing and shape is drawn once per engagement
from a seeded stream (a window, a chance, one of several variants). Contact reports are wide datums
on the plot, never firing solutions, and a tasking change always arrives with an order that says
what changed. The opposing side's decisions are never announced, except through a report a
player's own intelligence could plausibly make.

M35's opening hold (a 15 nm, five-minute station gate on one ship before any task could start) is
gone. Nothing could fail it by movement, so it was a fixed five-minute delay presented as a
decision, and losing the station ship in those five minutes locked every task. The destination
holds (`*_handover`) stay: holding the box is the delivery.
"""
from copy import deepcopy
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Bumped when the pass changes. A file already at or past it is left alone, so running this module
# on its own only re-encodes the shipped files; regenerate through the five builders.
REVISION = 26
# Each operation has a distinct command problem: one 2027 operation per chart region and three
# 1990 operations. M35 cut the overlapping missions; the two exercises stay on the Training shelf.
PLANS = {
 'cold_war_01_convoy': [('Form the escort', 'Decide where the frigates go: both close around North Star, or Elrod and its Seahawk ahead to find the corvette while Nicholas stays with the cargo.'), ('Clear the approaches', 'Classify every surface contact before firing. Coastal radar reports arrive as wide datums, not solutions, and not every contact on this route is hostile. Keep the shared Mk 13 magazines for missile defence.'), ('Deliver the convoy', 'Escort North Star into the handover box, then hold her there for five minutes. Watch for a change of box.')],
 'cold_war_02_barrier': [('Set the barrier', 'Put Dallas and the helicopters across the likely lanes. A loud Spruance can turn the boat from a transit into an attack.'), ('Localize the submarine', 'Fixed-array cues arrive as wide datums. Use passive bearings and spaced sonobuoys; a bearing or a cue is not a torpedo solution.'), ('Deny the passage', 'Stop the Victor III or maintain the barrier until the watch ends; a breakout still means defeat, and there may be more than one boat.')],
 'cold_war_03_carrier': [('Build the air picture', 'Get the Hawkeye and a Tomcat section up toward the threat axis. The raids keep no timetable: a second element follows once the enemy holds the group, or when it is provoked.'), ('Fight the raids or strike the cruiser', 'The four Intruders can put Harpoons into Slava from outside her SA-N-6 once she is located and classified. Alert, she shoots down most of a small salvo, so strike with all four; a hit brings the next raid at once, and every catapult and recovery slot the strike uses is one the Tomcats cannot.'), ('Recover and reset', 'Complete the two-hour watch and recover at least one aircraft. A carrier or cruiser loss still ends the operation.')],
 'pacific_02_taiwan_strait': [('Establish the picket', 'Put Hawkeye, CAP and the electronic-attack section up early; the KJ-500 holding the carrier is what brings the next raid and the next fighters.'), ('Meet the follow-on strike', 'Bomber elements arrive in separate waves and not always on the same axis. Protect the eastern pickets while the carrier cycles its larger air wing.'), ('Recover the air plan', 'Complete the five-hour watch and recover at least one aircraft. A surface kill alone does not cancel the air threat.')],
 'gulf_01_hormuz': [('Assemble the convoy', 'Order the tankers into the lane and place the escorts. Classify small craft before firing; UKMTO and coastal reports are datums, not solutions.'), ('Clear the strait', 'Escort at least two tankers through the mixed coastal, submarine and small-craft threat. The convoy passing Larak can bring out a second swarm, ahead or astern. Reserve short-range interceptors for leakers.'), ('Handover in the Gulf of Oman', 'Keep two tankers inside the destination box for five minutes; the transit deadline remains in force.')],
 'med_01_tartus': [('Cover the amphibious group', 'Get AEW and fighter cover up and keep Mistral behind the screen. Her progress east is what Khmeimim is watching.'), ('Cross the threat axis', 'Strike aircraft come in separate elements and not always from the same side of Cyprus. If the Bastion battery shows itself, the holding box can move.'), ('Secure the holding area', 'Keep Mistral in the holding box for five minutes after arrival. Civilian losses remain unacceptable.')],
 'aegis_bastion': [('Build the picket', 'Put Jack H. Lucas and Gettysburg between the group and the Kola and get airborne warning up. Keep the carrier and Maud farther back.'), ('Defend the force', 'Ballistic and low-altitude threats require different interceptors. The second Kinzhal element comes when Monchegorsk is ready, sooner if its ships are hit or its picture finds the carrier.'), ('Reset for another strike', 'Complete the four-hour watch and recover an aircraft. Launch reserve sections as the ready deck empties.')],
}
RECOVER = {'cold_war_03_carrier', 'pacific_02_taiwan_strait', 'aegis_bastion'}
# Later shore elements whose readiness an event decides. The authored time is only the fallback,
# beyond the latest moment the event can fire (Tartus: 10800 s plus its 300 s), so it never
# pre-empts the decision.
EVENT_READINESS = {
 'aegis_bastion': ('mig31k', 'su35s'),
 'pacific_02_taiwan_strait': ('j16',),
 'med_01_tartus': ('su34', 'su35s'),
}
READINESS_FALLBACK_S = 12600


def _modern_wing(host):
    """59-aircraft fictional US wing: 36 fighters, 5 EW, 4 AEW, 8 ASW, 6 utility.
    Sections, readiness and weapons are game estimates; no actual deployment is asserted.
    """
    wing = host.get('air_wing', [])
    fighters = [e for e in wing if e['platform'].startswith('usn_fighter_')]
    if not fighters:
        return
    out = []
    for e in wing:
        p = e['platform']
        e = deepcopy(e)
        if p.startswith('usn_fighter_'):
            e['count'] = 36 // len(fighters)
        else:
            e['count'] = {'usn_ea_ea18g': 5, 'usn_aew_e2d': 4, 'usn_helo_mh60r': 8, 'usn_helo_mh60s': 6}.get(p, e['count'])
        # The ready deck is deliberately limited. The rest still exist aboard and are lost
        # with the host, and they consume ordinary launch spots when their preparation ends.
        ready = deepcopy(e)
        ready['count'] = min(e['count'], 4 if 'fighter' in p else 2 if 'helo' in p else 1)
        reserve = deepcopy(e)
        reserve['count'] = e['count'] - ready['count']
        reserve['first_modex'] = e.get('first_modex', 1) + ready['count']
        reserve['ready_after_s'] = 1800 if 'fighter' in p else 1200
        if p in ('usn_fighter_fa18e', 'usn_fighter_fa18f'):
            ready['loadout'] = {'aim120_family': 6 if p.endswith('fa18e') else 2, 'aim9x_air': 2}
            reserve['loadout'] = {'aim120_family': 2, 'aim9x_air': 2, 'agm_158c_lrasm': 2}
            ready['squadron'] = e.get('squadron', 'Scenario section') + ' / CAP'
            reserve['squadron'] = e.get('squadron', 'Scenario section') + ' / maritime strike'
        out.append(ready)
        if reserve['count']:
            out.append(reserve)
    host['air_wing'] = out


def unique_wing_callsigns(d):
    names = {u['callsign'] for u in d['units']}
    for host in d['units']:
        for entry in host.get('air_wing', []):
            base = entry.get('callsign', entry.get('squadron', ''))
            if not base:
                continue
            first = entry.get('first_modex', 1)
            calls = [f'{base} {first+i}' for i in range(entry['count'])]
            if any(c in names for c in calls):
                base += ' ' + host['callsign'].split()[0]
                entry['callsign'] = base
                calls = [f'{base} {first+i}' for i in range(entry['count'])]
            names.update(calls)


# --- Event vocabulary -------------------------------------------------------------------------
# Small constructors for scripts/simulation/operation_director.gd's schema. Positions are nm
# about the chart anchor, as everywhere else in a scenario.

def reach(callsigns, center, radius, count=1):
    return dict(type='reach_area', callsigns=list(callsigns), center_nm=list(center), radius_nm=radius, count=count)


def held(faction, callsigns, at_least='UNKNOWN', **extra):
    """Whether `faction`'s own plot holds the named units, classified at least this far."""
    return dict(type='track_held', faction=faction, callsigns=list(callsigns), min_classification=at_least, **extra)


def damaged(callsigns, below=0.95):
    return dict(type='unit_damaged', callsigns=list(callsigns), health_below=below)


def lost(callsigns):
    return dict(type='all_units_lost', callsigns=list(callsigns))


def any_of(*conditions):
    return dict(type='any', of=list(conditions))


def report(target, error_nm, source):
    """A contact report: a datum within `error_nm` of the target, never a firing solution."""
    return dict(target=target, error_nm=error_nm, source=source)


def bonus(oid, callsigns, text, **condition):
    """A bonus task: credited by the assessment, never needed to win. Sinking by default."""
    return dict(id=oid, type=condition.pop('type', 'all_units_lost'), callsigns=list(callsigns), optional=True, text=text, **condition)


def ready(host, platform, after_s, count=None):
    out = dict(host=host, platform=platform, ready_after_s=after_s)
    if count is not None:
        out['count'] = count
    return out


def chart_text(d, xy):
    """A position as the chart labels it (Geo.format_latlon), for an order that names a place."""
    lat0, lon0 = d['map']['anchor_lat'], d['map']['anchor_lon']
    lat = lat0 + xy[1] / 60.0
    lon = lon0 + xy[0] / (60.0 * math.cos(math.radians(lat0)))

    def fmt(value, positive, negative):
        minutes = math.floor(abs(value) * 600.0 + 0.5) / 10.0
        return '%02d°%04.1f′%s' % (int(minutes // 60), minutes % 60, positive if value >= 0 else negative)
    return '%s %s' % (fmt(lat, 'N', 'S'), fmt(lon, 'E', 'W'))


def _unit(d, callsign):
    return next(u for u in d['units'] if u['callsign'] == callsign)


def _moved(unit, position, patrol, **extra):
    """A copy of an authored unit entering from somewhere else on another route."""
    u = deepcopy(unit)
    u['position_nm'] = list(position)
    u['patrol_nm'] = [list(p) for p in patrol]
    u.update(extra)
    return u


# --- The reactions, one command problem each -----------------------------------------------------

def _convoy(d):
    cargo, corvette = 'MV North Star', 'Soviet missile corvette (Nanuchka III)'
    new_box = [4.5, 22.5]
    second = 'Soviet missile corvette 2 (Nanuchka III)'
    coaster = 'MV Bergen Coaster'
    return [
        # Where the corvette waits is the enemy's choice: across the route, by the handover box,
        # or out on the eastern flank. The escort has to find out which.
        dict(id='corvette_station', side='RED', at_s=0, variants=[
            dict(id='across_the_route', ai=[dict(units=[corvette], patrol_nm=[[0.0, -3.0], [17.4, 21.0]])]),
            dict(id='at_the_box', ai=[dict(units=[corvette], patrol_nm=[[14.0, 20.0], [6.0, 22.0], [14.0, 12.0]])]),
            dict(id='eastern_flank', ai=[dict(units=[corvette], patrol_nm=[[22.0, 6.0], [8.0, -4.0], [22.0, 6.0]])])]),
        dict(id='coastal_report', at_s_window=[600, 1500], unless=held('BLUE', [corvette], allow_stale=True),
             intel=[report(corvette, 8, 'Norwegian coastal radar')],
             message='Norwegian coastal radar reports a fast surface contact near {pos}, accuracy about 8 nm. '
                     'Identify it before you shoot: the coasters on this route are neutral.'),
        # Halfway along, a second contact closes the route. Hostile or a neutral coaster, it is
        # reported the same way; only classification tells them apart.
        dict(id='second_contact', when=reach([cargo], [1.6, 3.6], 6), latest_s=5400, variants=[
            dict(id='second_corvette', weight=2, intel=[report(second, 6, 'Norwegian coastal radar')],
                 reinforcements=[dict(platform='cw90_nanuchka', callsign=second, faction='RED', position_nm=[24.0, 26.0],
                                      heading_deg=225, speed_kn=18, patrol_nm=[[12.0, 18.0], [4.0, 10.0]])]),
            dict(id='neutral_coaster', weight=3, intel=[report(coaster, 6, 'Norwegian coastal radar')],
                 reinforcements=[dict(platform='cw90_merchant', callsign=coaster, faction='NEUTRAL', position_nm=[24.0, 26.0],
                                      heading_deg=225, speed_kn=12, radar_on=True, patrol_nm=[[-10.0, -14.0]])])],
             message='Coastal radar: a second surface contact near {pos}, accuracy about 6 nm, closing the convoy route '
                     'from the north-east. Classify it before engaging.'),
        dict(id='handover_moved', chance=0.5, when=reach([cargo], [-1.2, -0.8], 5),
             objectives=dict(update={'handover': dict(center_nm=new_box, text='North Star reached the new handover box'),
                                     'handover_handover': dict(center_nm=new_box)}),
             message='TASKING UPDATE: the Norwegian escort group is delayed. The handover box moves about 8 nm north-west, '
                     'to %s. Steer North Star for the new box; the deadline is unchanged.' % chart_text(d, new_box)),
    ]


def _barrier(d):
    boat = 'Soviet submarine (Victor III)'
    gate = next(o for o in d['objectives']['loss'] if o['id'] == 'breakout')['center_nm']
    second = 'Soviet submarine 2 (Victor III)'
    return [
        dict(id='transit_lane', side='RED', at_s=0, variants=[
            dict(id='direct', ai=[dict(units=[boat], patrol_nm=[gate])]),
            dict(id='western', ai=[dict(units=[boat], patrol_nm=[[-5.0, 4.0], gate])]),
            dict(id='eastern', ai=[dict(units=[boat], patrol_nm=[[9.0, -2.0], gate])])]),
        dict(id='array_cue', at_s_window=[600, 1800], unless=held('BLUE', [boat], allow_stale=True),
             intel=[report(boat, 12, 'Fixed acoustic array')],
             message='Fixed acoustic array cue: a submerged contact near {pos}, accuracy about 12 nm. A cue is not a '
                     'firing solution; localize it with buoys or Dallas before committing a torpedo.'),
        # A commander who hears the escort may stop running and fight. Whether this one does is drawn.
        dict(id='boat_turns', side='RED', chance=0.6, when=held('RED', ['USS Spruance (DD 963)']),
             ai=[dict(units=[boat], ai_posture='standard')]),
        dict(id='second_boat', chance=0.35, at_s_window=[3600, 6000],
             reinforcements=[dict(platform='cw90_victor3', callsign=second, faction='RED', position_nm=[-14.0, 16.0],
                                  heading_deg=160, speed_kn=7, depth_m=160, radar_on=False, ai_posture='breakout',
                                  patrol_nm=[[-8.0, 2.0], gate])],
             intel=[report(second, 15, 'Fixed acoustic array')],
             objectives=dict(add_loss=[dict(id='breakout_2', type='reach_area', callsigns=[second], center_nm=gate, radius_nm=3,
                                            count=1, text='Second Victor III crossed the southern barrier')],
                             update={'neutralize': dict(callsigns=[boat, second], text='Neutralize both Victor IIIs')}),
             message='TASKING UPDATE: the fixed array holds a second submerged contact near {pos}, accuracy about 15 nm, '
                     'heading for the same gap. It must not cross the barrier either; neutralizing the boats now means both.'),
    ]


def _carrier(d):
    cv, slava, raid = 'USS Dwight D. Eisenhower (CVN 69)', 'Slava', 'Backfire raid 1'
    target = [4.5, 3.0]
    second = d.pop('_delayed')[0]
    third = _moved(second, [118.0, 206.0], [target], callsign='Backfire raid 3')
    return [
        dict(id='slava_station', side='RED', at_s=0, variants=[
            dict(id='inshore', ai=[dict(units=[slava], patrol_nm=[[47.0, 24.0], [94.0, 66.0]])]),
            dict(id='northern', ai=[dict(units=[slava], patrol_nm=[[60.0, 70.0], [100.0, 90.0]])]),
            dict(id='eastern', ai=[dict(units=[slava], patrol_nm=[[70.0, 0.0], [110.0, 30.0]])])]),
        dict(id='raid_ingress', side='RED', at_s=0, variants=[
            dict(id='direct', ai=[dict(units=[raid], patrol_nm=[target])]),
            dict(id='from_the_north', ai=[dict(units=[raid], patrol_nm=[[40.0, 150.0], target])]),
            dict(id='from_the_east', ai=[dict(units=[raid], patrol_nm=[[150.0, 90.0], target])])]),
        # The second element goes when the Northern Fleet's own picture holds the carrier, or at
        # once if its cruiser is attacked, never before its window; otherwise it goes anyway later.
        dict(id='follow_on_raid', side='RED', at_s_window=[900, 1800],
             when=any_of(held('RED', [cv], 'CLASS_KNOWN'), damaged([slava])), latest_s_window=[2700, 3600], variants=[
                 dict(id='north_single', weight=2, reinforcements=[second]),
                 dict(id='north_pair', weight=1, reinforcements=[second, third]),
                 dict(id='east_single', weight=2, reinforcements=[_moved(second, [230.0, 60.0], [target])])]),
        dict(id='cruiser_report', at_s_window=[300, 900], unless=lost([slava]),
             intel=[report(slava, 15, 'Norwegian P-3 Orion')], ready=[ready(cv, 'cw90_a6e', 600)],
             objectives=dict(add=[bonus('strike_slava', [slava], 'Put a Harpoon into Slava', type='unit_damaged', health_below=0.85)]),
             message='TASKING UPDATE: a Norwegian Orion reports a Soviet cruiser, probably Slava, near {pos}, accuracy about '
                     '15 nm. She carries sixteen Bazalts. The reserve Intruders are being readied: a Harpoon hit on her is a '
                     'bonus task, and the air-defence watch is still the mission.'),
    ]


def _aegis(d):
    kasatonov, soob, kilo, cv = 'Admiral Kasatonov (461)', 'Soobrazitelny (531)', 'Kaluga (B-800)', 'USS Dwight D. Eisenhower (CVN 69)'
    base = 'Monchegorsk Air Base'
    return [
        dict(id='surface_group_axis', side='RED', at_s=0, variants=[
            dict(id='coastal', ai=[dict(units=[kasatonov], patrol_nm=[[70.3, 12.0], [156.3, -42.0]]),
                                   dict(units=[soob], patrol_nm=[[86.0, 0.0], [168.0, -54.0]])]),
            dict(id='northern', ai=[dict(units=[kasatonov], patrol_nm=[[90.0, 50.0], [150.0, 10.0]]),
                                    dict(units=[soob], patrol_nm=[[100.0, 45.0], [160.0, 0.0]])])]),
        # Monchegorsk brings its second Kinzhal element and escorts up on its own schedule, or at
        # once when its ships are hit or its own picture holds the carrier.
        dict(id='kinzhal_second_element', side='RED', at_s=0, latest_s_window=[1800, 3300],
             when=any_of(damaged([kasatonov, soob], 0.9), held('RED', [cv], 'CLASS_KNOWN')),
             ready=[ready(base, 'mig31k', 300), ready(base, 'su35s', 300)]),
        dict(id='kinzhal_intercept', chance=0.7, after=['kinzhal_second_element'],
             message='Intercept: Monchegorsk is arming a second Kinzhal element and its escort. Expect ballistic rounds '
                     'within the next half hour.'),
        dict(id='kilo_report', at_s_window=[600, 2100], unless=lost([kilo]),
             intel=[report(kilo, 8, 'Norwegian P-3C')],
             objectives=dict(add=[bonus('sink_kaluga', [kilo], 'Sink the Kilo inside the screen')]),
             message='TASKING UPDATE: a Norwegian P-3C reports a snorkelling submarine, probably the Kilo, near {pos}, accuracy '
                     'about 8 nm, inside the screen. Sinking her is a bonus task; Maud and the carrier are still the mission.'),
    ]


def _taiwan(d):
    reagan, nanchang, xian = 'USS Ronald Reagan (CVN 76)', 'Nanchang (101)', "Xi'an (153)"
    delayed = d.pop('_delayed')
    southern = [_moved(u, [u['position_nm'][0] + 20.0, -120.0 - 8.0 * i], [[0.0, -60.0], [109.6, -24.0]]) for i, u in enumerate(delayed)]
    return [
        dict(id='follow_on_raid', side='RED', at_s_window=[1200, 2400], when=held('RED', [reagan], 'CLASS_KNOWN'),
             latest_s_window=[3000, 4500], variants=[
                 dict(id='northern_axis', reinforcements=delayed),
                 dict(id='southern_axis', reinforcements=southern)]),
        dict(id='huian_second_element', side='RED', at_s=0, when=held('RED', [reagan], 'CLASS_KNOWN'),
             latest_s_window=[2400, 4200], ready=[ready('Huian Air Base', 'j16', 600)]),
        dict(id='group_report', at_s_window=[900, 2100], unless=lost([nanchang, xian]),
             intel=[report(nanchang, 20, 'Kadena P-8')],
             objectives=dict(add=[bonus('surface_group', [nanchang, xian], "Neutralize Nanchang and Xi'an")]),
             message="TASKING UPDATE: Kadena's P-8 reports the PLAN surface group near {pos}, accuracy about 20 nm, working "
                     "south. Neutralizing Nanchang and Xi'an is a bonus task; the five-hour watch is still the mission."),
    ]


def _hormuz(d):
    tankers = ['MT Gulf Horizon', 'MT Ras Laffan Pride', 'MT Aegean Dawn']
    boat = _unit(d, 'Peykaap 1')

    def swarm(origin, route):
        return [_moved(boat, [origin[0] + 1.2 * (i % 2), origin[1] - 1.0 * i], route, callsign='Peykaap %d' % (7 + i)) for i in range(4)]
    return [
        # The convoy passing Larak is the signal for a second swarm, from ahead or from astern.
        dict(id='second_swarm', side='RED', chance=0.6, when=reach(tankers, [-13.4, 12.0], 6), variants=[
            dict(id='from_larak', reinforcements=swarm([-12.0, 30.0], [[0.0, 15.0], [13.0, -3.0]])),
            dict(id='from_qeshm', reinforcements=swarm([-30.0, 22.0], [[-20.0, 16.0], [-6.0, 10.0], [8.0, 2.0]]))]),
        dict(id='swarm_sighted', chance=0.7, after=['second_swarm'], intel=[report('Peykaap 7', 4, 'Omani coastal radar')],
             message='Omani coastal radar: a second group of fast boats near {pos}, accuracy about 4 nm, heading for the lane.'),
        dict(id='periscope_report', at_s_window=[900, 2700], unless=lost(['Ghadir']),
             intel=[report('Ghadir', 3, 'UKMTO relay from a dhow')],
             message="UKMTO relays a dhow's sighting of a periscope in the outbound lane near {pos}, accuracy about 3 nm."),
        dict(id='fire_mission', chance=0.7, at_s_window=[600, 1800], when=held('RED', tankers, 'CLASS_KNOWN'),
             objectives=dict(add=[bonus('drones_down', ['Mohajer 81', 'Mohajer 82'], 'Shoot down both Mohajer drones')]),
             message='TASKING UPDATE: intercepts show a Mohajer passing a tanker\'s position to the Khalij Fars battery. Expect '
                     'ballistic fire on the convoy. Shooting down both drones is a bonus task.'),
    ]


def _tartus(d):
    mistral, base, battery = 'FS Mistral (L 9013)', 'Khmeimim Air Base', 'Tartus coastal battery'
    box = next(o for o in d['objectives']['victory'] if o['id'] == 'holding_box')['center_nm']
    moved = [round(box[0] - 15.0, 4), box[1]]
    strikers = ['Fullback 21', 'Fullback 22', 'Fullback 23', 'Fullback 24']
    return [
        dict(id='strike_axis', side='RED', at_s=0, variants=[
            dict(id='direct', ai=[dict(units=strikers, patrol_nm=[[39.6, 12.0], [-19.8, -24.0]])]),
            dict(id='north_of_cyprus', ai=[dict(units=strikers, patrol_nm=[[30.0, 90.0], [-60.0, 80.0], [-50.0, -10.0]])]),
            dict(id='from_the_south', ai=[dict(units=strikers, patrol_nm=[[40.0, -40.0], [-20.0, -45.0]])])]),
        # Mistral getting well under way east (past about 32°20'E) is what Khmeimim waits for; a
        # transit held back for the picture leaves it to its own time.
        dict(id='khmeimim_surge', side='RED', at_s=0, when=reach([mistral], [-75.0, -26.0], 15), latest_s_window=[7200, 10800],
             ready=[ready(base, 'su34', 300), ready(base, 'su35s', 300)]),
        dict(id='surge_intercept', chance=0.7, after=['khmeimim_surge'],
             message='Akrotiri intercepts: Khmeimim is arming its second strike element.'),
        # Whether and when Akrotiri fixes the battery is drawn; it needs the battery to have radiated.
        dict(id='bastion_located', chance=0.65, at_s_window=[600, 2400], when=dict(type='emitting', callsigns=[battery]),
             intel=[report(battery, 4, 'Akrotiri ELINT')],
             objectives=dict(update={'holding_box': dict(center_nm=moved, text='Mistral reached the moved holding box'),
                                     'holding_box_handover': dict(center_nm=moved)}),
             message='TASKING UPDATE: ELINT has the Bastion battery radiating near {pos}, accuracy about 4 nm. Mistral\'s '
                     'holding box moves 15 nm west, to %s, outside its reach. The five-minute hold counts in the new box.'
                     % chart_text(d, moved)),
        dict(id='kilo_report', at_s_window=[900, 2400], unless=lost(['Krasnodar (B-265)']),
             intel=[report('Krasnodar (B-265)', 6, 'RAF Poseidon')],
             message='An RAF Poseidon reports a possible snorkel near {pos}, accuracy about 6 nm, on Mistral\'s side of the lane.'),
    ]


REACTIONS = {
    'cold_war_01_convoy': _convoy, 'cold_war_02_barrier': _barrier, 'cold_war_03_carrier': _carrier,
    'aegis_bastion': _aegis, 'pacific_02_taiwan_strait': _taiwan, 'gulf_01_hormuz': _hormuz, 'med_01_tartus': _tartus,
}


def _domain(platform):
    """A catalogue platform's domain, read from its resource as the builders write it."""
    for folder in (ROOT / 'data/platforms').iterdir():
        path = folder / (platform + '.tres')
        if path.exists():
            for line in path.read_text().splitlines():
                if line.startswith('domain = '):
                    return json.loads(line.split('= ', 1)[1])
            return 'surface'
    raise ValueError('unknown platform ' + platform)


def _check_geometry(d):
    """The builders check the opening force against the coast before this pass runs. Units that
    enter by event, routes an event gives a unit, and boxes it moves are checked here the same way."""
    import geography as g
    units, boxes = [], []
    for e in d['events']:
        for shape in [e] + e.get('variants', []):
            units.extend(shape.get('reinforcements', []))
            for order in shape.get('ai', []):
                for name in order['units']:
                    host = next((u for u in d['units'] if u['callsign'] == name), None)
                    if host is not None and 'patrol_nm' in order:
                        units.append(dict(host, callsign='%s (%s)' % (name, e['id']), patrol_nm=order['patrol_nm']))
            update = shape.get('objectives', {})
            for change in update.get('update', {}).values():
                if 'center_nm' in change:
                    boxes.append(dict(id=e['id'], type='reach_area', center_nm=change['center_nm']))
            boxes.extend(o for o in update.get('add', []) + update.get('add_loss', []) if o['type'] == 'reach_area')
    g.validate_scenario(dict(id=d['id'], terrain=d['terrain'], units=units, objectives=dict(victory=boxes)), _domain)


def enhance(d):
    if d.get('operation_revision', 0) >= REVISION:
        return d
    sid = d['id']
    d['operation_revision'] = REVISION
    d['collection'] = 'operations' if sid in PLANS else 'exercises'
    if sid not in PLANS:
        return d
    d['operation_plan'] = [dict(title=f'{i+1:02d} / {title}', task=task) for i, (title, task) in enumerate(PLANS[sid])]
    original = d['objectives']['victory']
    # Full carrier watches cannot be ended early by killing a cruiser while follow-on aircraft
    # are still scheduled. The surface targets come back as bonus tasks once they are reported.
    if sid in RECOVER and d.get('victory_mode') == 'any':
        original = [o for o in original if o['type'] == 'time_elapsed']
        d['victory_mode'] = 'all'
    d['objectives']['victory'] = original
    # Arrival is followed by a real on-station task, not a drive-through victory.
    for o in list(original):
        if o['type'] == 'reach_area':
            o['phase_only'] = True
            hold = deepcopy(o)
            hold.update(id=o['id']+'_handover', type='hold_area', seconds=300, phase_only=False,
                        after=[o['id']], text='Hold the required vessels in the destination box for five continuous minutes')
            d['objectives']['victory'].append(hold)
    if sid in RECOVER:
        d['objectives']['victory'].append(dict(id='recover_air_plan', type='aircraft_recovered', faction='BLUE',
            count=1, text='Recover at least one aircraft after a sortie'))
    d['objectives']['text'] = ' '.join(task for _, task in PLANS[sid])
    d['commander_intent'] = PLANS[sid][-1][1]
    d['first_orders'].append('F1 lists the operation sequence, live task progress and tasking updates. Contact reports go on the '
                             'plot as wide datums to investigate; they are never firing solutions.')
    for host in d['units']:
        host['aviation_reload_cycles'] = 2
        if host['faction'] == 'BLUE' and host['platform'] in ('usn_cvn_nimitz', 'usn_cvn_ford'):
            _modern_wing(host)
        # Shore attacks arrive in elements rather than one opening dump of every airframe.
        elif host['faction'] == 'RED' and host.get('air_wing'):
            wing = []
            for entry in host['air_wing']:
                first = deepcopy(entry)
                if entry['count'] >= 2 and any(k in entry['platform'] for k in ('bomber', 'strike', 'tu22', 'fighter')):
                    first['count'] = max(1, entry['count']//2)
                    later = deepcopy(entry)
                    later['count'] -= first['count']
                    later['first_modex'] = entry.get('first_modex', 1) + first['count']
                    decided = any(k in entry['platform'] for k in EVENT_READINESS.get(sid, ()))
                    later['ready_after_s'] = READINESS_FALLBACK_S if decided else 2400
                    wing.extend([first, later])
                else:
                    wing.append(first)
            host['air_wing'] = wing
        elif host['platform'] == 'cw90_nimitz':
            # A fleet-defence detachment with a small period strike element: four A-6E TRAM with
            # Harpoon, two on deck and two in reserve. No Hornet, Prowler or tanker squadrons.
            host['air_wing'] = [dict(platform=p, count=n, callsign=call, first_modex=first, ready_after_s=delay)
                for p,n,call,first,delay in [('cw90_f14a',4,'Tomcat',101,0),('cw90_f14a',8,'Tomcat',105,1800),
                  ('cw90_e2c',1,'Hawkeye',601,0),('cw90_e2c',3,'Hawkeye',602,1200),
                  ('cw90_a6e',2,'Intruder',501,0),('cw90_a6e',2,'Intruder',503,2400),
                  ('cw90_s3a',4,'Viking',701,0),('cw90_sh3h',4,'Sea King',801,0)]]
    # The hand-placed follow-on raids leave the opening force and enter by event, without
    # adding weapons or changing their authored ingress.
    delayed = [u for u in d['units'] if (sid=='cold_war_03_carrier' and u['callsign']=='Backfire raid 2') or
                (sid=='pacific_02_taiwan_strait' and u['callsign'] in ('Badger 3','Badger 4'))]
    d['units'] = [u for u in d['units'] if u not in delayed]
    d['_delayed'] = delayed
    d['events'] = REACTIONS[sid](d)
    d.pop('_delayed', None)
    _check_geometry(d)
    unique_wing_callsigns(d)
    for old in ('CVW-3 det', 'CVW-5 det'):
        d['forces'] = d.get('forces', '').replace(old, 'fictional 59-aircraft wing')
    if sid == 'pacific_02_taiwan_strait':
        d['forces'] = d['forces'].replace('4 H-6J airborne', '4 H-6J in two raid elements')
    if sid == 'cold_war_03_carrier':
        d['description'] = d['description'].replace('Two Backfire-C aircraft are inbound', 'Backfire-C aircraft approach in separate raid elements')
        d['description'] = d['description'].replace('Tomcats, Hawkeye, Vikings and Sea Kings', 'Tomcats, Hawkeyes, Vikings, Sea Kings and four Harpoon-armed Intruders')
        d['forces'] = d['forces'].replace('F-14A+, E-2C, S-3A', 'F-14A+, E-2C, A-6E, S-3A').replace('2 Backfire-C', 'Backfire-C raid elements')
        d['first_orders'][-2] = ('Reserve SM-2 for leakers and recall aircraft before fuel exhaustion. The Intruders can strike Slava '
                                 'from outside her SA-N-6 once she is located and classified; that is a bonus, not the task.')
    d['force_note'] = ('Fictional operation. Modern US carriers carry 59 represented aircraft with a limited ready deck; '
                       '1990 carriers carry a 28-aircraft fleet-defence detachment with a four-aircraft A-6E Harpoon element, '
                       'not a complete historical air wing. '
                       'Other wings remain scenario detachments. Aircraft already carry their first load; each base has two additional '
                       'wing reloads, shared by weapon type. Readiness, stores and all combat performance are game estimates.')
    d['description'] += (' This operation reacts to what each side sees: raid timing, enemy readiness, contact reports and '
                         'tasking change from one engagement to the next. Consult the operation sequence before deployment.')
    return d


if __name__ == '__main__':
    for path in sorted((ROOT/'data/scenarios').glob('*.json')):
        d = json.loads(path.read_text())
        enhance(d)
        path.write_text(json.dumps(d, indent=2, ensure_ascii=False)+'\n')
    ops = sum(path.stem in PLANS for path in (ROOT/'data/scenarios').glob('*.json'))
    total = len(list((ROOT/'data/scenarios').glob('*.json')))
    print(f'Updated {ops} operations; retained {total - ops} exercises.')
