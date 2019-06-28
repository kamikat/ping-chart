# ping+chart

Show ping statistics in [asciichart](https://github.com/kroitor/asciichart).

![screenshot.png](docs/screenshot.png)

## Basic Usage

Create `servers.lst` like:

    192.168.1.1
    1.234.56.78
    8.8.8.8
    1.2.3.4

Plot realtime ping chart of packet loss statistics (default metrics):

    bash ping+chart.sh

Available metrics:

- **sent** - packets sent
- **receive** - packets received
- **loss (default)** - % packet loss
- **avg** - average RTT value in millisecond
- **min** - minumum RTT value
- **max** - maximum RTT value
- **mdev** - standard deviation on RTT

E.g, plot average network latency statistics:

    bash chart+ping.sh avg

_It may take minutes to generate a single chart._

## Advanced Usage

### Multiple Chart Display

Collect ping statistics in separate process:

    bash ping.sh | tee ping.log

Plot chart continously:

    bash ping+chart.sh -f ping.log [other chart options]

### Take Snapshot

Export chart script:

    bash ping+chart.sh -q -r > loss-chart.cs

Plot chart from snapshot:

    bash chart.sh < loss-chart.cs

## TODOs

- [ ] better performance
- [ ] Y-axis auto down scale (too slow)
- [x] chart legend display
- [x] tweak color scheme

## License

(The MIT License)
