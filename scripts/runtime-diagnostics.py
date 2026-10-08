#!/usr/bin/env python3
"""Read-only Wine/Steam and system-memory snapshot. Prints JSON to stdout."""
import datetime
import json
import plistlib
import re
import subprocess


def output(*args):
    return subprocess.check_output(args, text=True)


processes = []
for line in output("ps", "-axo", "pid=,ppid=,state=,%cpu=,rss=,comm=").splitlines():
    fields = line.strip().split(None, 5)
    if len(fields) != 6:
        continue
    name = fields[5]
    if re.search(r"wine|steam\.exe|steamwebhelper|/Steam/|b1-Win64|b1\.exe", name, re.I):
        processes.append(dict(pid=int(fields[0]), parent=int(fields[1]), state=fields[2],
                              ps_cpu_percent=float(fields[3]), rss_kib=int(fields[4]), executable=name))

graphics = []
wine_clients = []
try:
    registry = plistlib.loads(subprocess.check_output(["ioreg", "-r", "-c", "AGXAccelerator", "-a"]))

    def visit(value):
        if isinstance(value, dict):
            stats = value.get("PerformanceStatistics")
            if isinstance(stats, dict) and "In use system memory" in stats:
                graphics.append(dict(in_use_bytes=stats.get("In use system memory"),
                                     allocated_bytes=stats.get("Alloc system memory")))
            creator = value.get("IOUserClientCreator", "")
            if isinstance(creator, str) and "wine" in creator.lower():
                wine_clients.append(dict(creator=creator, queues=value.get("CommandQueueCount")))
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(registry)
    # Some driver versions expose client statistics only in the text form.
    if not wine_clients:
        text = output("ioreg", "-r", "-c", "AGXAccelerator", "-l")
        wine_clients.extend(dict(creator=creator, queues=int(queues)) for creator, queues in
                            re.findall(r'"IOUserClientCreator" = "(pid \d+, wine[^\"]*)"\s*\n[^\n]*"CommandQueueCount" = (\d+)', text))
except (subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
    graphics.append(dict(error=str(error)))

vm = output("vm_stat")
page_size = int(re.search(r"page size of (\d+) bytes", vm).group(1))
memory = {key: int(count) * page_size for key, count in
          re.findall(r"^(Pages (?:free|active|inactive|wired down|occupied by compressor)):\s+(\d+)", vm, re.M)}
print(json.dumps(dict(timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                     processes=processes, graphics=graphics, wine_graphics_clients=wine_clients,
                     memory_bytes=memory, swap=output("sysctl", "vm.swapusage").strip(),
                     cpu_note="ps CPU is a decaying average; use top interval samples for a controlled comparison."), indent=2))
