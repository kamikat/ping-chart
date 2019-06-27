# chart+ping

Show ping statistics in [asciichart](https://github.com/kroitor/asciichart).

![screenshot.png](docs/screenshot.png)

## Basic Usage

Generate `servers.lst` (a TSV file contains IPv4 addresses)

For Vultr API:

    http https://api.vultr.com/v1/server/list API-Key:<MY-VULTR-API-KEY> | jq -r 'to_entries | .[].value | [.main_ip, .location] | @tsv' | tee servers.lst

Plot realtime ping chart (packet loss):

    bash chart+ping.sh

Chart options:

- **sent** - packets sent
- **receive** - packets received
- **loss (default)** - % packet loss
- **avg** - average RTT (round-trip time) in millisecond
- **min** - minumum RTT in millisecond
- **max** - maximum RTT in millisecond
- **mdev** - standard deviation on RTT

Plot average network latency:

    bash chart+ping.sh avg

## Advanced Usage

Collect ping statistics in separate process:

    bash ping.sh | tee ping.log

Plot chart:

    bash chart+ping.sh -f ping.log

## TODOs

- [ ] better performance
- [ ] chart title / legend
- [ ] tweak color scheme

## License

(The MIT License)
