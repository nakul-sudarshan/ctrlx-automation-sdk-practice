# Exercise 1: Write CPU measurements to the Active Configuration

## 1. Purpose and starting point
These changes were made as an attempt at implementing Exercise 1 from the [ctrlX AUTOMATION SDK-II course](https://academy.boschrexroth.com/de_de/ctrlx-automation-sdk-ii-en.html).

The original SDK sample reads ctrlX Data Layer nodes and prints their values to
the console. This exercise extends it to store CPU utilisation measurements in:

```text
$SNAP_COMMON/solutions/activeConfiguration/exercise1/cpu_usage.txt
```

The current implementation keeps the latest **150 measurements**, with one
percentage value per line, formatted to two decimal places:

```text
12.34
14.78
11.02
```

The file contains numbers only: no timestamps, percent signs, or header.

This document describes the current source files and their differences from the
SDK sample at the local repository's `HEAD`. It does not claim that the modified
snap has been built or verified on a device.

The official solution from the course can be viewed in [solution_code_snippets_file.zip](./solution_code_snippets_file.zip)

## 2. Files changed or added

| File | Change | Purpose |
|---|---|---|
| [main.cpp](./main.cpp) | Modified | Write successful CPU reads to a bounded history file; fix the connection fallback pointer assignment. |
| [snap/snapcraft.yaml](./snap/snapcraft.yaml) | Modified | Grant Active Configuration access, start through a wrapper, package the wrapper, and declare the connection hook. |
| [scripts/start.sh](./scripts/start.sh) | Added | Wait for the required interfaces and Active Configuration before starting C++. |
| [snap/hooks/connect-plug-active-solution](./snap/hooks/connect-plug-active-solution) | Added | Initialize the exercise directory when the content plug connects. |

Source layout:

```text
datalayer.client.simple/
├── main.cpp
├── scripts/
│   └── start.sh
├── snap/
│   ├── snapcraft.yaml
│   └── hooks/
│       └── connect-plug-active-solution
└── Exercise1_changes.md
```

No CMake or build-script changes were required for these additions. The sample
already selects C++20, which supports the standard filesystem facilities used
here. The new shell wrapper is packaged by a separate Snapcraft dump part.

## 3. Active Configuration access in snapcraft.yaml

### 3.1 Define the content plug

The following top-level plug was added:

```yaml
plugs:
  active-solution:
    interface: content
    content: solutions
    target: $SNAP_COMMON/solutions
```

The existing `datalayer` plug remains alongside it.

- `active-solution` is the local plug name used by the app, hook, and startup
  checks. Its spelling must match everywhere.
- `interface: content` requests access to content shared by another snap.
- `content: solutions` identifies the shared content.
- `target` specifies where that content is made visible inside this snap.

The Solutions app provides the storage. Its `activeConfiguration` symlink
identifies the currently active configuration's app-data location.

Declaring this plug does **not** create a new configuration, connect the
interface by itself, or start another executable. The plug must actually be
connected to the appropriate Solutions slot.

### 3.2 Attach the plug to the existing service

The service now uses:

```yaml
apps:
  app:
    command: bin/start.sh
    plugs:
      - network
      - datalayer
      - active-solution
    daemon: simple
    passthrough:
      restart-condition: always
      restart-delay: 10s
```

Compared with the base sample:

1. `active-solution` was added to the existing service's plugs.
2. `command` changed from `datalayerClientSimple` to `bin/start.sh`.
3. The existing daemon and restart settings were retained.

There is no separate Active Configuration service. The wrapper eventually
starts the original C++ executable.

The commented-out app block in the current YAML is only a reference; it has no
effect. There must be only one uncommented `app:` definition under `apps:`.

### 3.3 Package the wrapper

A new part copies the wrapper from the source tree into the snap:

```yaml
parts:
  startup:
    plugin: dump
    source: ./scripts
    organize:
      start.sh: bin/start.sh
```

The original `datalayerclient` part is retained.

`organize` maps the source file `scripts/start.sh` to `bin/start.sh` inside the
snap. At runtime, that packaged path is `$SNAP/bin/start.sh`.

A `stage` filter alone would not perform this move. Keeping the source wrapper
outside `generated/build` also prevents it from being deleted when the build
scripts regenerate build outputs.

### 3.4 Declare hook access

The following declaration was added:

```yaml
hooks:
  connect-plug-active-solution:
    plugs: [active-solution]
```

This grants the named hook access to the content plug. The hook implementation
is the executable file under `snap/hooks/`, not the YAML block itself.

## 4. Startup wrapper: scripts/start.sh

The wrapper is a normal service command, **not a hook**:

```sh
#!/bin/sh
set -eu

for plug in datalayer active-solution; do
  until snapctl is-connected "$plug"; do
    echo "Waiting for plug $plug to be connected..."
    sleep 5
  done
done

until [ -d "$SNAP_COMMON/solutions/activeConfiguration" ]; do
  echo "Waiting for the active configuration directory"
  sleep 5
done

exec "$SNAP/datalayerClientSimple"
```

### Why wait here?

A service can start before its content interfaces are connected. Starting the
C++ program immediately could cause it to access unavailable Data Layer or
configuration resources.

Instead of assuming that a fixed startup delay is sufficient, the wrapper
checks actual readiness:

1. Wait until `datalayer` is connected.
2. Wait until `active-solution` is connected.
3. Wait until `activeConfiguration` resolves to an accessible directory.
4. Replace the wrapper process with the C++ executable using `exec`.

Each unsuccessful check sleeps for **five seconds** in the current script.
When all checks already succeed, there is no deliberate startup delay.

`exec` allows the C++ process to receive service signals directly instead of
remaining a child of a waiting shell.

`set -e` stops the script on an unhandled command failure, and `set -u` treats
unset variables as errors. The failed connection checks are intentionally
handled by the `until` loops.

The loops do not establish interface connections. If a required plug never
connects or the configuration directory never becomes available, startup keeps
waiting and logs the reason. Interface connection also does not guarantee that
the Data Layer broker is already accepting client connections.

## 5. Connection hook

The hook is located at:

```text
snap/hooks/connect-plug-active-solution
```

It has no `.sh` extension. Snapcraft packages executable hooks from this
directory.

Current implementation:

```sh
#!/bin/sh
set -eu

CONFIG_ROOT="$SNAP_COMMON/solutions/activeConfiguration"
MYDIR="$CONFIG_ROOT/exercise1"

if [ ! -d "$CONFIG_ROOT" ]; then
    echo "Active configuration directory is unavailable: $CONFIG_ROOT" >&2
    exit 1
fi

mkdir -p "$MYDIR"
echo "Configuration directory ready: $MYDIR"
```

The hook:

- Checks that the Active Configuration exists before creating anything below it.
- Creates the app-specific `exercise1` directory.
- Uses quoted paths.
- Uses `mkdir -p` so an existing directory is not an error.
- Reports failure rather than continuing as if initialization succeeded.

This runs as part of plug connection, not on every measurement, every service
start, or every Active Configuration change. It does not read CPU values,
create the history file, or launch the C++ program.

The C++ writer also creates/checks `exercise1` on each write. It therefore does
not rely solely on the hook having initialized the currently selected
configuration.

### Executable permissions

Both scripts must be executable. From the sample directory:

```sh
chmod +x scripts/start.sh snap/hooks/connect-plug-active-solution
```

Both files were executable when this document was prepared.

## 6. C++ changes in main.cpp

### 6.1 Additional standard headers

| Header | Use |
|---|---|
| `<cstdlib>` | Retrieve `SNAP_COMMON` with `std::getenv`. |
| `<filesystem>` | Construct paths, check directories, create directories, and rename files. |
| `<fstream>` | Read existing measurements and write the replacement history. |
| `<iomanip>` | Format measurements to two decimal places. |
| `<system_error>` | Receive filesystem errors through `std::error_code`. |
| `<deque>` | Retain a bounded sequence of previous measurement lines. |
| `<string>` | Store each line read from the existing file. |

### 6.2 New helper: writeCpuUsage

The new function:

```cpp
static bool writeCpuUsage(double cpuUsage)
```

returns `true` only after successfully replacing the output file. Failures are
reported to `std::cerr` and return `false`.

#### Resolve the runtime storage path

The helper retrieves:

```cpp
const char *snapCommon = std::getenv("SNAP_COMMON");
```

It rejects a missing or empty value. C++ does not expand shell expressions such
as `$SNAP_COMMON` inside string literals.

It constructs the Active Configuration path using:

```cpp
const auto configRoot =
    std::filesystem::path(snapCommon) / "solutions" / "activeConfiguration";
```

It first verifies that this path is a directory, then creates `exercise1` with
`std::filesystem::create_directories`. It does not intentionally create a
replacement Active Configuration root if the shared storage is unavailable.

The final paths are:

```text
exercise1/cpu_usage.txt
exercise1/cpu_usage.txt.tmp
```

Both are beneath the selected Active Configuration.

#### Retain the latest 150 measurements

The limit is:

```cpp
constexpr std::size_t maxEntries = 150;
```

If the destination exists, the helper reads it line by line:

```cpp
std::deque<std::string> entries;

std::string line;
while (std::getline(input, line))
{
  entries.push_back(line);
  if (entries.size() >= maxEntries)
  {
    entries.pop_front();
  }
}
```

The `>=` comparison is intentional: the deque retains at most **149 previous
lines**, leaving room for the new measurement.

After adding the new value:

| Successful measurement | File contents |
|---|---|
| 1 | Measurement 1 |
| 150 | Measurements 1 through 150 |
| 151 | Measurements 2 through 151 |
| 152 | Measurements 3 through 152 |

The file is not cleared wholesale after 150 entries. Only the oldest
measurement is dropped as a new one arrives.

Because history is loaded from the file rather than tracked only in memory,
the limit works across process restarts and trims a pre-existing oversized file
on the next successful update. Existing lines are treated as entries without
validating that each is a CPU number; this assumes the app owns the file.

#### Write and replace the file

The helper opens the temporary file in truncation mode:

```cpp
std::ofstream output(temporaryPath, std::ios::out | std::ios::trunc);
```

It writes the retained lines, then the newest value:

```cpp
for (const auto &entry : entries)
{
  output << entry << '\n';
}

output << std::fixed << std::setprecision(2) << cpuUsage << '\n';
output.close();
```

After checking that writing and closing succeeded, it replaces the destination:

```cpp
std::filesystem::rename(temporaryPath, outputPath, error);
```

On Linux, a successful rename within the same directory atomically replaces
the destination name. Readers opening the destination do not see the intermediate
partially written replacement. A reader already holding the old file open can
continue reading that old version and must reopen to see the new one.

This is not a guarantee of durability across sudden power loss: the current
implementation does not explicitly synchronize the file and directory to disk.
It assumes one writer and no concurrent Active Configuration switch during an
individual update. A failed update can leave the temporary file behind; the
next attempt truncates and reuses it.

#### Error handling

The helper checks and logs:

- Missing `SNAP_COMMON`.
- Unavailable Active Configuration.
- Failure to create the exercise directory.
- Failure to inspect, open, or read existing history.
- Failure to open, write, or close the temporary file.
- Failure to rename the temporary file over the destination.

It does not substitute a different storage location or report success on a
failed write.

### 6.3 Call the helper after a successful CPU read

The original Data Layer address remains:

```text
framework/metrics/system/cpu-utilisation-percent
```

The existing `readSync` result and `FLOAT64` type checks remain. Inside the
successful branch, the value is extracted once and passed to the writer:

```cpp
const double cpuUsage = double(cpuUtilisationPercentValue);

std::cout << "INFO Value of " << cpuUtilisationPercentAddress
          << ": " << cpuUsage << " %" << std::endl;

if (writeCpuUsage(cpuUsage))
{
  std::cout << "INFO CPU usage file updated" << std::endl;
}
```

A failed read or unexpected type does not add an entry. A failed write is
logged, but does not stop the loop; the app tries again after its next
successful CPU read.

The existing `framework/state` read and console output remain unchanged and
are not written to this file.

### 6.4 Fix the connection fallback pointer

The base sample deleted the first client and then declared another
`dataLayerClient` inside the fallback block:

```cpp
auto dataLayerClient = datalayerSystem.factory()->createClient3(connectionString2);
```

That inner variable shadowed the outer pointer. The main loop could then use
the outer pointer after its object had been deleted.

The declaration was changed to an assignment:

```cpp
dataLayerClient = datalayerSystem.factory()->createClient3(connectionString2);
```

The outer pointer now refers to the replacement client used by the main loop
and final cleanup.

## 7. Timing and retention

The existing main loop still ends with:

```cpp
sleep(2);
```

Therefore:

- There is one write attempt per successful, correctly typed CPU read.
- The normal interval is approximately two seconds **plus** Data Layer reads,
  file operations, logging, and scheduling time.
- The nominal frequency is approximately 0.5 Hz, not a precise fixed rate.
- 150 measurements represent roughly five minutes of samples, potentially
  longer if reads fail or operations take longer.

The startup wrapper's five-second polling interval is unrelated to the
measurement interval. Similarly, the service's ten-second restart delay
applies to restarts, not regular writes.

## 8. End-to-end sequence

```text
Solutions content plug connects
  -> Connection hook checks activeConfiguration
  -> Hook creates exercise1

Service starts
  -> bin/start.sh waits for both plugs and activeConfiguration
  -> exec starts datalayerClientSimple
  -> C++ starts the Data Layer system and client
  -> Successful FLOAT64 CPU read
  -> Writer checks the active storage and exercise directory
  -> Writer retains up to 149 previous lines
  -> Writer adds the newest value to a temporary file
  -> Rename publishes the new cpu_usage.txt
  -> Remaining loop work and sleep(2)
  -> Repeat while the client remains connected
```

The two startup paths are distinct lifecycle events. The wrapper's readiness
checks and the C++ directory check avoid relying on the hook as a general
service-start mechanism.

## 9. Build and runtime verification checklist

These are verification steps, not a record of completed device testing.

1. Confirm both scripts are executable and pass shell syntax checks:

   ```sh
   sh -n scripts/start.sh
   sh -n snap/hooks/connect-plug-active-solution
   ```

2. Build the sample for the required architecture using its existing build
   workflow. Confirm that the packaged snap contains:
   - `datalayerClientSimple`
   - Executable `bin/start.sh`
   - Executable `meta/hooks/connect-plug-active-solution`

3. After an authorized deployment, inspect connections and logs on ctrlX:

   ```sh
   snap connections sdk-cpp-client-simple
   snap logs sdk-cpp-client-simple.app -n=50
   ```

   Confirm both required content plugs are connected. Repeated startup wait
   messages identify missing readiness conditions.

4. Open a shell in the app's snap context:

   ```sh
   snap run --shell sdk-cpp-client-simple.app
   ```

   Then inspect the output:

   ```sh
   ls -ld "$SNAP_COMMON/solutions/activeConfiguration/exercise1"
   cat "$SNAP_COMMON/solutions/activeConfiguration/exercise1/cpu_usage.txt"
   wc -l "$SNAP_COMMON/solutions/activeConfiguration/exercise1/cpu_usage.txt"
   ```

5. Observe the line count grow to 150. After more successful updates, confirm
   it stays at 150 while new values appear at the end. Identical consecutive
   CPU values are possible, so line contents alone may not prove every update.

6. Check logs for write errors. Do not infer success just because the process
   is running.

Running the C++ executable directly outside a snap does not provide
`SNAP_COMMON` or the connected Solutions storage. The writer reports that
condition instead of writing to an arbitrary local directory.

## 10. Scope and limitations

- This exercise publishes a text history; it does not register a new Data Layer
  node or implement the Solutions save/load callback protocol.
- The history is limited to 150 lines, but the file is read and rewritten on
  every successful update.
- Opening paths afresh avoids deliberately retaining a file descriptor into an
  old configuration across writes. It does not coordinate configuration
  switching during a write.
- Active Configuration storage is suitable for this learning exercise, but
  continuous production telemetry is better handled by a dedicated logging
  or time-series solution with suitable storage and retention policies.
- The current source was inspected for this document. Snap build, device
  confinement, actual interface connections, and end-to-end file updates still
  require runtime verification.

## References

- [SDK: Persisting App Data](https://boschrexroth.github.io/ctrlx-automation-sdk/4.6.0/persistdata.html)
- [Sample README](./README.md)
- [Sample source](./main.cpp)
- [Snapcraft configuration](./snap/snapcraft.yaml)
