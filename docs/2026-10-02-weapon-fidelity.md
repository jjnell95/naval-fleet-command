# Weapon geometry and command fidelity

The launch solution, terminal seeker, and firing board now distinguish three decisions:

- Is the held contact a permitted target and within the weapon's launch envelope?
- Can the represented mount bear on that solution, or must the crew turn the ship?
- What might the weapon actually acquire after reaching its terminal search area?

## Terminal acquisition

Initial acquisition and decoy reacquisition use the same forward sector. The sector is intersected with the whole movement segment and seeker radius, so a fast round cannot skip a narrow basket, acquire a ship already astern when the seeker enables, or claim an impact that happened before acquisition. The default 35-degree half angle is a gameplay estimate, not a measured seeker specification.

The seeker cannot read contact identities or faction labels. It may acquire neutral or friendly traffic in its search sector. The firing platform itself remains excluded. Commander ROE and protected-identity launch restrictions still apply to the designated held track; they cannot immunize another ship against a missile already in flight.

The firing board and chart warn about protected contacts reported near the terminal search area. These warnings use only the shooter's held reports and their positional uncertainty; they neither read hidden unit positions nor certify that a corridor is clear. The warning area deliberately errs on the side of caution when either plot is uncertain.

## Guidance updates

A terminal active seeker no longer grants every weapon live midcourse retargeting. `WeaponSpec.midcourse_updates` explicitly enables supported updates; command and semi-active radar weapons also update while their radar support is available. Updates require a living shooter holding an active track. Losing updates leaves an autonomous weapon on its last solution; losing required radar support ends a command/semi-active shot.

Authored update-capable fits include the represented active radar AAMs, Aster/SM-6/Sea Ceptor, selected modern strike weapons, and AIM-54A. Harpoon Block 1C, the represented NSM, unguided gunfire and other unlisted launch-and-leave fits retain their launch solutions. These capability selections are broad gameplay abstractions: datalink message intervals, relay topology, illumination beam scheduling and wire-guided torpedo commands remain outside this change. The existing public identity and weapon-family sources are listed in `DATA_SOURCES.md`, `docs/COLD_WAR_1990.md` and `docs/THEATRES_2027.md`.

## Mount arcs and crew maneuver

`PlatformSpec.weapon_mount_arcs` stores one or more relative mount sectors per weapon. The represented Burke, Nansen, Udaloy and Slava bow guns have an aft masked sector. Ticonderoga and Sovremennyy fore/aft mounts contribute a union of sectors. The 1990 Perry's forward Mk 13 and aft-facing Mk 75 use separate sectors. A true VLS fit remains unrestricted by hull bearing. Unauthored mounts retain their existing unrestricted behavior.

Mount positions follow the represented public fit. Sector widths and the five-degree unmasking margin are gameplay estimates, not operational firing limitations. Other mount-specific obstructions and damage to individual mounts are not modeled here.

A masked firing-board row says **Mount masked / Attack to unmask**. A standing Attack task turns to clear the nearest sector, holds its ammunition until ready, and reports **Turning to engage**. The task then fires normally. This avoids displaying an ongoing turn when the player has only inspected a weapon.

## Verification

The focused regression set covers swept acquisition, astern and abeam rejection, neutral/friendly acquisition, supported versus fixed launch solutions, loss of the update source, semi-active radar support, combined mount sectors, the VLS exception, automatic unmasking before ammunition expenditure, and warnings based only on held protected reports. Existing tests that asserted omnidirectional astern acquisition were corrected to the new forward-search behavior; impact and run-out checks were retained.
