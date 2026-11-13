# Energy Shield Dome

A shield generator for Factorio 2.1 + Space Age that grows an energy dome over your base. The dome replaces walls, not turrets: enemies and their acid cannot get in, while your own shots fly out freely. Everything it does costs power, so a weak grid means a weak shield.

## How it works

- **Build it on Fulgora.** The generator (7×7) is crafted in an electromagnetic plant from supercapacitors, superconductors, processing units, refined concrete and accumulators. One fits in a rocket, so you ship it to the planet you want to protect.
- **Deploy.** Connect power and set the radius. The generator charges its buffer, then the dome grows outward tile by tile. Enemy units caught by the growing front are burned. Growth stops 4 tiles short of enemy nests and worms.
- **Hold.** A thin vector outline with a soft edge glow marks the dome; hits send ripples along it. Enemies and their attacks are blocked; players, vehicles and your projectiles pass.
- **Pay.** Deploying costs power per tile of area, holding the dome costs upkeep per tile, and every absorbed hit costs power. That includes your own nukes going off nearby. If the pool runs dry, or a single hit is bigger than the buffer, the dome collapses and recharges after 15 s.
- **Electric field.** Up to 6 tiles outside the edge, enemies take electric damage that fades with distance. Nests and worms take half. Electric weapons damage research boosts it with no cap. The field only spends energy above a reserve you choose (0–95 %, default 50 %), and can be switched off.

## Numbers

| | Normal | Legendary |
|---|---|---|
| Buffer | 5 GJ | 12.5 GJ |
| Max charging rate | 500 MW | 1 GW |
| Max radius (base / after 3 radius techs) | 64 / 160 | 84 / 180 |
| Field width | 6 tiles | 11 tiles |

- Deploy 0.25 MJ per tile of area, upkeep 3 kW per tile, 40 kJ per absorbed HP.
- A full r = 160 dome takes ~20 GJ to deploy and ~240 MW to hold.
- **Several generators:** up to 4 generators can power one dome (map setting, 1–8). Energy is shared and the maximum radius grows with √n (4 generators: ×2). A generator joins a dome once that dome's radius reaches it; the first generator stays the centre. Domes that only touch stay separate and are drawn as one merged bubble.

## Technologies

All need automation, logistic, chemical, military, utility and electromagnetic science packs.

- **Energy shield dome**: 1500 units, unlocks the generator.
- **Dome radius 1–3**: 1000 / 2000 / 3000 units, +32 max radius each.
- **Dome radius 4+** (infinite): 4000 × 2^(L−4) units, +16 max radius per level.

## Planets

- Nauvis, Gleba and other planets from mods: works.
- Fulgora: the magnetic field is too dense; the dome does not deploy (you can only build it there).
- Vulcanus, Aquilo: not available yet.
- Space platforms: not allowed.

## Interface

- **Generator window** (click the generator): state with collapse countdown, role in a multi-generator dome, pooled buffer, upkeep, radius slider, on/off, electric field on/off and field reserve slider, combat statistics.
- **Entity status** (hover): state, kills, damage dealt and damage absorbed.
- **Map view** (shortcut bar or Ctrl+Shift+D): generator markers, dome edges, field zones and hit flashes.
- **Alerts**: "under attack" points at the hit location, "collapsed" points at the dome centre. Can be turned off per player.
- Settings are kept in blueprints and copied with Shift+right/left click.

## Settings

- Map: **Maximum dome radius cap** (0 = no limit), **Maximum generators per dome** (1–8, default 4).
- Per player: **Dome edge glow** (on by default), **Shield dome alerts** (on by default).

## Notes

- Electric field damage scales with the tesla damage bonus; vanilla electric weapons damage technologies show an extra "Shield dome field damage" line.
- Enemy acid streams from shooters just outside the edge are stopped before they land, unless something of yours outside the dome is within the shooter's reach.
- Gleba pentapods that step over the barrier are pushed back out at an energy cost.
- Balance is a first pass and will be tuned from play feedback, especially for Gleba.

## Credits

- Generator model, remnants, icons and thumbnail were made in Blender for this mod.
- Made with the help of **Claude** (Anthropic's AI assistant, via Claude Code): code, 3D model, testing, balance numbers and this description were made together with it.

## License

MIT, see [LICENSE](LICENSE).

---

### Кратко по-русски

Генератор щита растит энергетический купол над базой. Купол — это стена, а не турель: враги и их кислота не проходят внутрь, наши выстрелы летят наружу свободно. Развёртывание, поддержание и каждый поглощённый удар стоят энергии; если сети не хватает, купол рушится и перезаряжается. Электрическое поле бьёт врагов в 6 клетках за краем, усиливается исследованиями урона электрического оружия. Крафт только на Фульгоре, до 4 генераторов на купол (настройка карты), качество повышает буфер, зарядку, радиус и ширину поля.

Мод сделан с помощью ИИ-ассистента Claude (Anthropic).
