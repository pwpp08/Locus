# Locus

A health app for your wearable that keeps everything on your phone. No
account, no subscription, no cloud: the band's raw data is synced over
Bluetooth, stored in a local database and turned into scores on the device.

Licensed under AGPL-3.0.

## What it does

- **Recovery, sleep and strain** every day, scored against your own baselines
  rather than population averages, with the reasons behind each number.
- **Sleep** staging, sleep need and debt, latency, consistency and a sleep
  planner that tells you when to go to bed for tomorrow's wake time.
- **Smart alarm** on the band: a silent buzz at a set time, or once you have
  slept what you need.
- **Health**: live heart rate, Locus Age and your pace of aging, an overnight
  health monitor (respiratory rate, resting heart rate, HRV, skin temperature,
  and SpO2 on wearables that measure it), a stress monitor and a journal that
  finds what actually moves your numbers.
- **Energy reserve** through the day, charged by rest and drained by stress
  and effort.
- **Activity**: auto-detected workouts, live tracking with GPS routes, a
  strength trainer, heart-rate zones and VO2max.
- **AI coach** with your own API key: it reads your data on the phone and
  answers with your numbers, plans workouts and logs things for you.
- **Community** (opt-in): teams and a leaderboard.
- **Your data, elsewhere**: writes to Apple Health and Health Connect, exports
  the whole database, and keeps scheduled local backups.

The full list is in [docs/FEATURES.md](docs/FEATURES.md).

## Devices

| Device | Support |
|:--|:--|
| WHOOP 4.0, 5.0, MG | Full: every score is computed from these |
| Bluetooth heart-rate straps | Workouts |
| Oura, Garmin, Coros, Ultrahuman, Colmi, Mi Band | Experimental: pair and store their data; scores from them are switched on once checked on real hardware |
| Galaxy Watch, Fitbit and other watches | Side by side through Health Connect / Apple Health |

The phone's own step counter fills in steps on bands without one.

## Getting started

Download the APK from the latest
[release](https://github.com/pwpp08/Locus/releases), or build from source with
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Guides

- [Development: build and run from source](docs/DEVELOPMENT.md)
- [Features](docs/FEATURES.md)
- [AI coach](guides/AI_COACH.md)
- [Tasker integration](guides/TASKER_INTEGRATION.md)
- [Buzz meanings](guides/BUZZ_MEANINGS.md)
- [Writing a device adapter](docs/ADAPTERS.md)

## Contributing

Bug reports from real devices are the most useful thing you can send. Pull
requests are welcome: read [CONTRIBUTING.md](CONTRIBUTING.md) first. Security
issues go through [SECURITY.md](SECURITY.md).

## Privacy

Everything stays on your phone unless you opt in. Details in
[PRIVACY.md](PRIVACY.md).

## Disclaimer

Locus is independent and not affiliated with or endorsed by WHOOP, Oura,
Garmin, Samsung or any other device maker. Product names are trademarks of
their owners and are used only to describe compatibility. Locus is not a
medical device; its numbers are estimates.

## License

AGPL-3.0. See [LICENSE](LICENSE).
