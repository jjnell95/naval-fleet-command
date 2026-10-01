"""Authored operation structure applied by every scenario builder. Idempotent on shipped JSON.

All scheduling, air readiness and magazine budgets are fictional game design, not real plans.
Theatre identity and geometry remain owned by the original geographic scenario builders.
"""
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Each operation has a distinct command problem: one 2027 operation per chart region and three
# 1990 operations. M35 cut the overlapping missions; the two exercises stay on the Training shelf.
PLANS = {
 'cold_war_01_convoy': [('Form the escort', 'Keep the two frigates with North Star while the convoy forms.'), ('Clear the approaches', 'Classify the coastal contacts. Keep the shared Mk 13 magazines available for missile defence.'), ('Deliver the convoy', 'Escort North Star into the destination box, then hold her there for five minutes.')],
 'cold_war_02_barrier': [('Establish the barrier', 'Hold Dallas on the opening patrol station for five minutes while Spruance deploys its helicopters.'), ('Localize the submarine', 'Use passive bearings and spaced sonobuoys. A bearing alone is not a torpedo solution.'), ('Deny the passage', 'Stop the Victor III or maintain the barrier until the watch ends; a breakout still means defeat.')],
 'cold_war_03_carrier': [('Build the air picture', 'Keep Bunker Hill on the opening station while launching Hawkeye and a Tomcat section.'), ('Fight successive raids', 'A second Backfire element may follow the first. Keep reserve fighters and the point-defence layer available.'), ('Recover and reset', 'Complete the two-hour watch and recover at least one aircraft. A carrier or cruiser loss still ends the operation.')],
 'pacific_02_taiwan_strait': [('Establish the picket', 'Hold Robert Smalls on station while Hawkeye, CAP and the electronic-attack section build the picture.'), ('Meet the follow-on strike', 'Bomber elements arrive in separate waves. Protect the eastern pickets while the carrier cycles its larger air wing.'), ('Recover the air plan', 'Complete the five-hour watch and recover at least one aircraft. A surface kill alone does not cancel the air threat.')],
 'gulf_01_hormuz': [('Assemble the convoy', 'Keep Paul Ignatius on the opening station while the tankers form up. Classify small craft before firing.'), ('Clear the strait', 'Escort at least two tankers through the mixed coastal, submarine and small-craft threat. Reserve short-range interceptors for leakers.'), ('Handover in the Gulf of Oman', 'Keep two tankers inside the destination box for five minutes; the transit deadline remains in force.')],
 'med_01_tartus': [('Cover the amphibious group', 'Hold Andrea Doria on station while AEW and fighter cover go up. Keep Mistral behind the screen.'), ('Cross the threat axis', 'Strike aircraft become ready in separate elements. Use the finite Exocet and fighter stocks deliberately.'), ('Secure the holding area', 'Keep Mistral in the holding box for five minutes after arrival. Civilian losses remain unacceptable.')],
 'aegis_bastion': [('Establish the radar picket', 'Hold Jack H. Lucas on the opening station. Keep the carrier farther back and build airborne warning.'), ('Defend the force', 'Ballistic and low-altitude threats require different interceptors. The point-defence layer keeps its own allowance.'), ('Reset for another strike', 'Complete the four-hour watch and recover an aircraft. Launch reserve sections as the ready deck empties.')],
}
STATION = {
 'cold_war_01_convoy': 'USS Elrod (FFG 55)', 'cold_war_02_barrier': 'USS Dallas (SSN 700)',
 'cold_war_03_carrier': 'USS Bunker Hill (CG 52)', 'pacific_02_taiwan_strait': 'USS Robert Smalls (CG 62)',
 'gulf_01_hormuz': 'USS Paul Ignatius (DDG 117)', 'med_01_tartus': 'ITS Andrea Doria (D 553)',
 'aegis_bastion': 'USS Jack H. Lucas (DDG 125)',
}
RECOVER = {'cold_war_03_carrier', 'pacific_02_taiwan_strait', 'aegis_bastion'}


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


def enhance(d):
    if d.get('operation_revision') == 25:
        return d
    sid = d['id']
    d['operation_revision'] = 25
    d['collection'] = 'operations' if sid in PLANS else 'exercises'
    if sid not in PLANS:
        return d
    d['operation_plan'] = [dict(title=f'{i+1:02d} / {title}', task=task) for i, (title, task) in enumerate(PLANS[sid])]
    station = next(u for u in d['units'] if u['callsign'] == STATION[sid])
    prepare = dict(id='establish_screen', type='hold_area', callsigns=[station['callsign']],
                   center_nm=station['position_nm'][:], radius_nm=15, count=1, seconds=300,
                   phase_only=True, text=f"Keep {station['callsign']} within 15 nm of its opening station for five continuous minutes")
    original = d['objectives']['victory']
    # Full carrier watches cannot be ended early by killing a cruiser while follow-on aircraft
    # are still scheduled. Other denial missions retain their original alternative victory.
    if sid in RECOVER and d.get('victory_mode') == 'any':
        original = [o for o in original if o['type'] == 'time_elapsed']
        d['victory_mode'] = 'all'
    for o in original:
        o['after'] = ['establish_screen']
    d['objectives']['victory'] = [prepare] + original
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
            count=1, after=['establish_screen'], text='Recover at least one aircraft after a sortie'))
    d['objectives']['text'] = ' '.join(task for _, task in PLANS[sid])
    d['commander_intent'] = PLANS[sid][-1][1]
    d['first_orders'].append('Hold the named opening station for five minutes; F1 lists the operation sequence and live task progress.')
    d['events'] = [dict(id='screen_orders', after=['establish_screen'], at_s=300,
                         message='Screen established. Continue the operation sequence in F1; maintain coverage while aircraft cycle.')]
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
                    later['ready_after_s'] = 2400
                    wing.extend([first, later])
                else:
                    wing.append(first)
            host['air_wing'] = wing
        elif host['platform'] == 'cw90_nimitz':
            # Fleet-defence detachment, explicitly not the omitted Intruder/Hornet strike wing.
            host['air_wing'] = [dict(platform=p, count=n, callsign=call, first_modex=first, ready_after_s=delay)
                for p,n,call,first,delay in [('cw90_f14a',4,'Tomcat',101,0),('cw90_f14a',8,'Tomcat',105,1800),
                  ('cw90_e2c',1,'Hawkeye',601,0),('cw90_e2c',3,'Hawkeye',602,1200),
                  ('cw90_s3a',4,'Viking',701,0),('cw90_sh3h',4,'Sea King',801,0)]]
    # Split the hand-placed raids without adding weapons or changing their authored ingress.
    delayed = [u for u in d['units'] if (sid=='cold_war_03_carrier' and u['callsign']=='Backfire raid 2') or
                (sid=='pacific_02_taiwan_strait' and u['callsign'] in ('Badger 3','Badger 4'))]
    if delayed:
        d['units'] = [u for u in d['units'] if u not in delayed]
        d['events'].append(dict(id='follow_on_raid', at_s=2400, reinforcements=delayed))
        # No message naming invisible aircraft or exact positions is sent to the player.
    unique_wing_callsigns(d)
    for old in ('CVW-3 det', 'CVW-5 det'):
        d['forces'] = d.get('forces', '').replace(old, 'fictional 59-aircraft wing')
    if sid == 'pacific_02_taiwan_strait':
        d['forces'] = d['forces'].replace('4 H-6J airborne', '4 H-6J in two raid elements')
    if sid == 'cold_war_03_carrier':
        d['description'] = d['description'].replace('Two Backfire-C aircraft are inbound', 'Two Backfire-C aircraft approach in separate raid elements')
    d['force_note'] = ('Fictional operation. Modern US carriers carry 59 represented aircraft with a limited ready deck; '
                       '1990 carriers carry a 24-aircraft fleet-defence detachment, not a complete historical strike wing. '
                       'Other wings remain scenario detachments. Aircraft already carry their first load; each base has two additional '
                       'wing reloads, shared by weapon type. Readiness, stores and all combat performance are game estimates.')
    d['description'] += ' This expanded operation has staged tasks, finite aviation reload stocks and reserve readiness. Consult the operation sequence before deployment.'
    return d


if __name__ == '__main__':
    for path in sorted((ROOT/'data/scenarios').glob('*.json')):
        d = json.loads(path.read_text())
        enhance(d)
        path.write_text(json.dumps(d, indent=2, ensure_ascii=False)+'\n')
    ops = sum(path.stem in PLANS for path in (ROOT/'data/scenarios').glob('*.json'))
    total = len(list((ROOT/'data/scenarios').glob('*.json')))
    print(f'Updated {ops} operations; retained {total - ops} exercises.')
