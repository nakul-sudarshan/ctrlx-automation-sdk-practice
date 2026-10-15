# Exercise 2: Random float generation and square roots in the Data Layer

## 1. Goal and starting point
This is an attempted solution of Exercise 2 from the [ctrlX AUTOMATION SDK-II course](https://academy.boschrexroth.com/de_de/ctrlx-automation-sdk-ii-en.html)

The starting point is the SDK's C++ **Data Layer Provider Simple** sample in
`samples-cpp/datalayer.provider.simple`.

The original sample already starts a Data Layer provider, registers nodes of
different data types, supplies metadata through a metadata database, monitors the
provider connection, and unregisters its nodes during shutdown.

This exercise extends that sample without replacing its existing nodes:

1. Generate a random input from **0.00 to 10000.00 inclusive**.
2. Calculate the input's square root.
3. Log the input and result.
4. Repeat approximately every second while connected.
5. Expose the latest square root as a read-only `float32` node in the existing
   Data Layer branch.

No client request is needed to generate an input or perform the calculation.
However, the application still needs a working connection to the Data Layer
broker to operate as a provider.

The official solution can be found in [solution_code_snippets_sqrt-method.zip](./solution_code_snippets_sqrt-method.zip)

## 2. Why this sample was selected

A **provider** exposes nodes to the Data Layer. A **client** reads, writes, or
otherwise accesses nodes supplied by providers.

Because this exercise adds a new value to the Data Layer tree,
`datalayer.provider.simple` is the appropriate base. Its existing provider
connection, node registration, metadata handling, and shutdown sequence can all
be reused.

The final tree contains:

```text
sdk/cpp/datalayer/provider/simple/
|-- myString       Existing string node
|-- myFloat        Existing float32 node
|-- myInt64        Existing int64 node
|-- myFlatbuffer   Existing structured-data node
`-- sqrt           New read-only float32 square-root result
```

The existing `myFloat` node is not used as the random input and is not
automatically changed by this exercise. The random input is logged; it is not
exposed as an additional Data Layer node.

## 3. Files changed compared with the cloned baseline

| File | Change |
|---|---|
| [main.cpp](./main.cpp) | Added random generation, square-root calculation, a read-only provider node, registration, periodic updates, and shutdown unregistration. |
| [.vscode/c_cpp_properties.json](./.vscode/c_cpp_properties.json) | Aligned IntelliSense with C++20, GCC on Linux x64, and the current CMake Tools extension identifier. |
| [snap/snapcraft.yaml](./snap/snapcraft.yaml) | Updated the app description to mention random inputs, periodic calculation, logging, and the new node. |
| [README.md](./README.md) | Documented the added node, ranges, update interval, and read behavior. |
| [../../CHANGELOG.md](../../CHANGELOG.md) | Recorded the user-visible extension under the existing 4.6.0 changes section. |
| [Exercise2_changes.md](./Exercise2_changes.md) | Added this detailed explanation. |

The remaining sections explain the final implementation, rather than treating
earlier suggested code as though it were still present.

## 4. Additional includes in the application

The following includes were added to [main.cpp](./main.cpp):

```cpp
#include <cmath>
#include <atomic>
#include <iomanip>
#include <random>
#include <sstream>

#include "comm/datalayer/metadata_helper.h"
```

| Include | Purpose |
|---|---|
| `<cmath>` | Provides `std::sqrt()` for the square-root calculation. |
| `<atomic>` | Provides safe sharing of the latest result between the main loop and Data Layer read callbacks. |
| `<iomanip>` | Provides `std::fixed` and `std::setprecision()` for log formatting. |
| `<random>` | Provides the random engine, seed source, and uniform integer distribution. |
| `<sstream>` | Builds a complete log message without changing `std::cout`'s persistent numeric formatting. |
| `metadata_helper.h` | Provides the SDK helper used to describe the new node programmatically. |

These standard C++ facilities do not require adding a third-party package.

## 5. New SquareRootNode class

The new class is placed after the original `MyProviderNode` class and before
`main()`:

```cpp
class SquareRootNode : public MyProviderNode
{
private:
  std::mt19937 m_randomEngine{std::random_device{}()};
  std::uniform_int_distribution<int> m_inputHundredths{0, 1000000};
  std::atomic<float> m_result{0.0f};

public:
  SquareRootNode()
    : MyProviderNode(comm::datalayer::Variant{})
  {
    updateRandomValue();
  }

  // Additional member functions are explained below.
};
```

### 5.1 Reusing the existing provider-node interface

Deriving from `MyProviderNode` reuses its existing handling of create, remove,
and browse requests. The new class overrides reading, writing, and metadata
because those operations have different behavior for the square-root node.

The empty `Variant` passed to the base constructor is not the square-root
storage. The new node stores its result in `m_result`, and its overridden
`onRead()` returns that value instead of the base class's stored variant.

The original `MyProviderNode` implementation remains unchanged for the four
original sample nodes.

### 5.2 Random engine and seed

```cpp
std::mt19937 m_randomEngine{std::random_device{}()};
```

`std::mt19937` is a pseudorandom number generator. It is initialized once per node
instance using `std::random_device`, rather than being reseeded for every
calculation. It is suitable for this demonstration, not for cryptographic use.

### 5.3 Inclusive range and two-decimal-place inputs

```cpp
std::uniform_int_distribution<int> m_inputHundredths{0, 1000000};
```

The distribution chooses an integer from `0` through `1000000`, including both
endpoints. Dividing by `100.0f` gives the intended values:

```text
0       ->     0.00
1       ->     0.01
12345   ->   123.45
1000000 -> 10000.00
```

There are 1,000,001 possible input steps. Sampling integer hundredths makes the
inclusive upper bound and decimal step explicit. Values can repeat; a random
sample is not required to be different from the preceding sample.

The inputs are stored as binary `float` values, so most decimal hundredths are
represented approximately. Two decimal places describe the intended input
grid and displayed log format, not exact decimal arithmetic.

### 5.4 Shared result storage

```cpp
std::atomic<float> m_result{0.0f};
```

The main loop writes the result, while provider callbacks may read it from
another thread. Atomic storage avoids a data race on this shared float.

Only the main thread calls `updateRandomValue()`, so the random engine and
distribution are not shared with read callbacks.

### 5.5 Initial calculation

The constructor calls `updateRandomValue()`. Therefore, the first result is
calculated and logged before the node is registered. Once registration succeeds,
the node already has a valid result rather than waiting for the first one-second
interval.

## 6. Generating, calculating, storing, and logging

The new update function is:

```cpp
void updateRandomValue()
{
  const float input = static_cast<float>(m_inputHundredths(m_randomEngine)) / 100.0f;
  const float result = std::sqrt(input);
  m_result.store(result);

  std::ostringstream message;
  message << "INFO sqrt input=" << std::fixed << std::setprecision(2)
          << input << " result=" << std::setprecision(6) << result;
  std::cout << message.str() << std::endl;
}
```

The function:

1. Samples an integer number of hundredths.
2. Converts it to `float` and divides by `100.0f`.
3. Calculates `std::sqrt(input)`.
4. Stores the result atomically for Data Layer reads.
5. Logs the input with two decimal places and the result with six decimal places.

Because all generated inputs are finite and non-negative, there is no
client-provided negative input or type mismatch to validate in this calculation
path.

The output range is **0.0 through 100.0**, since:

```text
sqrt(0.00)     =   0.0
sqrt(10000.00) = 100.0
```

An illustrative log line is:

```text
INFO sqrt input=625.00 result=25.000000
```

The log's six decimal places are presentation formatting. The Data Layer stores
and returns the `float32` result; it does not store a formatted string.

## 7. Reading the result from the Data Layer

The new node overrides `onRead()`:

```cpp
void onRead(
  const std::string&,
  const comm::datalayer::Variant*,
  const ResponseCallback& callback) override
{
  using namespace comm::datalayer;

  Variant output;
  const auto result = output.setValue(m_result.load());
  callback(result, STATUS_FAILED(result) ? nullptr : &output);
}
```

Unlike the earlier client-input design, the request's data argument is not
used. A client simply reads:

```text
sdk/cpp/datalayer/provider/simple/sqrt
```

The callback loads the latest atomic result and puts it into a Data Layer
`Variant`. Passing a C++ `float` to `setValue()` produces a `float32` value.

The actual `setValue()` status is passed back to the caller. If it fails, the
callback receives no output value instead of a success-shaped response.

Reading the node does **not** generate a new input, trigger another calculation,
or change the update interval. Multiple reads between updates return the same
stored result.

## 8. Making the node read-only

The original sample node supports writing. That is not appropriate for a value
computed internally, so the new class overrides `onWrite()`:

```cpp
void onWrite(
  const std::string&,
  const comm::datalayer::Variant*,
  const ResponseCallback& callback) override
{
  callback(comm::datalayer::DlResult::DL_UNSUPPORTED, nullptr);
}
```

This prevents a write request that reaches the provider from overwriting the
calculated result. Read-only behavior is also declared in the node metadata.

## 9. Programmatic metadata for the new node

The new `onMetadata()` implementation creates metadata directly:

```cpp
Variant metadata;
MetadataHelper::createMetadata(
  metadata,
  NodeClass_Variable,
  true, false, false, false, false,
  {{"readType", "types/datalayer/float32"}},
  "Latest square root of a random float32 from 0.00 to 10000.00, updated every second.");

callback(DlResult::DL_OK, &metadata);
```

The operation flags following `NodeClass_Variable` mean:

| Operation | Allowed |
|---|---|
| Read | Yes |
| Write | No |
| Create | No |
| Delete | No |
| Browse | No children are supplied by this node |

The `readType` reference identifies the returned value as the existing built-in
`types/datalayer/float32` type.

The final node uses **Variable**, not **Method**, as its node class. The earlier
proposal calculated a result from an argument supplied by a client. The final
requirement instead exposes a continuously updated value, so a read-only variable
accurately describes the implemented behavior.

There is no new FlatBuffers schema or custom type registration for this scalar
float result. The original FlatBuffers schema and metadata database remain
necessary for the original sample functionality.

No entry was added for `sqrt` in [metadata.csv](./metadata.csv): its metadata
comes from this callback. The original nodes continue to use the existing
metadata database.

## 10. Registering the node alongside the original nodes

After obtaining and validating the provider connection, `main()` now creates and
registers the new node:

```cpp
SquareRootNode squareRootNode;
const std::string squareRootPath = dlBasePath + "sqrt";

const auto squareRootResult =
  provider->registerNode(squareRootPath, &squareRootNode);
```

The unchanged base path is:

```cpp
std::string dlBasePath = "sdk/cpp/datalayer/provider/simple/";
```

Appending `"sqrt"` places the new value in the same branch as the original
nodes. Registration of `myString`, `myFloat`, `myInt64`, and `myFlatbuffer` still
follows.

The node is a local object in `main()`, not a temporary object inside a smaller
scope. It stays alive during the application's main loop and provider shutdown.

### Registration failure

The added registration block checks `squareRootResult`. If registration fails:

1. The node path and SDK error text are written to standard error.
2. The provider is stopped and deleted.
3. The Data Layer system is stopped.
4. The process returns exit code `1`.

This avoids continuing as though the exercise's required node had been
successfully registered.

## 11. Updating the result from the existing main loop

Originally, the loop monitored the provider connection and slept for one second.
The following logic was added after that existing sleep:

```cpp
std::this_thread::sleep_for(std::chrono::milliseconds(1000));
if (!g_endProcess && provider->isConnected())
{
  squareRootNode.updateRandomValue();
}
```

The extra checks avoid calculating another value after a shutdown request or
after a detected connection loss during the sleep.

The interval is **approximately** one second, not a hard real-time deadline.
Calculation, logging, scheduling, and other work add to the sleep duration.
There is no new timer thread or client app needed for these updates.

The original connection-loss handling still ends the loop. The existing snap
restart configuration can then restart the process after it exits.

## 12. Unregistering the node during shutdown

Alongside the original node-unregistration calls, the following line was added:

```cpp
provider->unregisterNode(squareRootPath);
```

This occurs before stopping and deleting the provider and before stopping the
Data Layer system. The `squareRootNode` object remains alive throughout this
sequence and is destroyed automatically when `main()` returns.

## 13. Editor configuration changes

The current [.vscode/c_cpp_properties.json](./.vscode/c_cpp_properties.json)
contains these changes relative to the cloned baseline:

| Setting | Original | Current |
|---|---|---|
| `cppStandard` | `c++17` | `c++20` |
| `intelliSenseMode` | `clang-x64` | `linux-gcc-x64` |
| `configurationProvider` | `vector-of-bool.cmake-tools` | `ms-vscode.cmake-tools` |

These changes align editor analysis with the C++20 build configuration and the
current CMake Tools extension identifier. They do not change runtime behavior or
add libraries to the snap.

The `compilerPath` remains `/usr/bin/gcc`. Changing it to `/usr/bin/g++` was
recommended during the configuration review, but that recommendation has not
been applied in the current file.

### Workspace selection and the root CMake setting

The sample's debugger paths and task definitions assume that the sample folder
itself is opened as the VS Code workspace.

The repository-root [VS Code settings](../../.vscode/settings.json) currently
contain a separate local setting pointing `cmake.sourceDirectory` at the
repository's `cmake` directory. That directory contains SDK archive-extraction
logic rather than this sample's application project.

That root setting is not required by this exercise and has not been corrected
as part of it. If opening the entire SDK repository instead of the sample folder,
the recommended application source-directory setting is:

```json
"cmake.sourceDirectory": "${workspaceFolder}/samples-cpp/datalayer.provider.simple"
```

Opening this sample folder directly is the simpler way to use its existing
launch configurations and tasks unchanged.

## 14. Snap packaging changes and settings retained

Only the description in [snap/snapcraft.yaml](./snap/snapcraft.yaml) was changed
for this exercise. It now explains that the app generates random floats, logs
their square roots, and exposes the latest result through `sqrt`.

The following functional packaging settings remain unchanged:

| Setting | Reason it is retained |
|---|---|
| `name: sdk-cpp-provider-simple` | Keeps the existing snap identity. |
| `command: datalayerProviderSimple` | Matches the existing CMake executable target. |
| `base: core24` | Keeps the sample's existing runtime base. |
| `confinement: strict` | Retains the sample's confinement model. |
| `daemon: simple` | Runs the application continuously as a service. |
| `network` and `datalayer` plugs | Retains the original network and Data Layer interfaces. |
| Data Layer content target `$SNAP_DATA/.datalayer` | Retains access to the Data Layer IPC interface. |
| `restart-condition: always` and `restart-delay: 10s` | Retains automatic process restarting. |
| `ctrlx-datalayer` stage package | Retains the runtime Data Layer library. |
| `compiled` part | Still includes the original schema and metadata database. |
| `amd64` and `arm64` platforms | Retains the original target architectures. |

Random generation, square-root calculation, and standard-output logging require
no additional snap plug or third-party package.

The absence of a client-input dependency does not make the app independent of
the Data Layer broker. The existing provider connection is still required.

## 15. Build and generated files left unchanged

No exercise-specific changes were needed in:

- [CMakeLists.txt](./CMakeLists.txt): already builds the application with C++20
  and links its existing runtime dependencies.
- [build-snap-amd64.sh](./build-snap-amd64.sh) and
  [build-snap-arm64.sh](./build-snap-arm64.sh): retain the original packaging
  entry points for their respective architectures.
- [build-debug.sh](./build-debug.sh): retains the original debug build setup.
- [build-fbs.sh](./build-fbs.sh) and [build-mddb.sh](./build-mddb.sh): continue
  generating artifacts needed by the original nodes.
- [sampleSchema.fbs](./sampleSchema.fbs) and [metadata.csv](./metadata.csv):
  no new schema or metadata database entry is needed for the built-in float type.
- [ctrlx_datalayer_helper.h](./ctrlx_datalayer_helper.h): the existing provider
  connection helpers are reused.
- [.vscode/tasks.json](./.vscode/tasks.json) and
  [.vscode/launch.json](./.vscode/launch.json): the executable and workspace
  layout have not been renamed.

No generated schema code or binary schema was manually edited for this feature.

## 16. Documentation changes

The sample [README](./README.md) now states:

- The exact new node path.
- Its `float32` output type and read-only behavior.
- The input and output ranges.
- Startup and approximately one-second updates.
- That no client argument is required.
- That reading does not trigger another calculation.
- That the node supplies its metadata programmatically.

The repository [changelog](../../CHANGELOG.md) records the feature under the
existing 4.6.0 changes section.

## 17. Verification performed and remaining deployment checks

### Local verification already performed

A temporary standalone C++ test compiled the modified application source into a
local test harness and checked 10,000 generated samples. It verified:

- Inputs stay between `0.00` and `10000.00`.
- Inputs are logged with two decimal places.
- Results are `float32` values between `0.0` and `100.0`.
- Returned results match `std::sqrt()` of the logged input within the test's
  floating-point tolerance.
- Logged and returned results agree within the test's tolerance.
- Repeated reads without an update return the same result.
- Metadata declares a read-only variable with the `float32` read type.
- Direct write callbacks reject writes with `DL_UNSUPPORTED`.

The editor also reported no C++ errors in the modified source.
The temporary test source and executable were removed afterward.

This is local functional evidence, not a completed snap-build or device test.
The 10,000-sample check does not prove that both random endpoints were sampled;
the inclusive bounds come from the integer distribution configuration.

### Build limitation observed

An attempted build through CMake Tools failed during configuration. The CMake
diagnostics tool reported no diagnostics. The repository-root source-directory
setting described above is a likely configuration issue, but the tool did not
provide enough detail to confirm it as the sole cause.

### Checks to perform on a target

After building and installing the snap using the normal SDK workflow:

1. Confirm the app service is running and connected to the Data Layer.
2. Inspect the logs:

   ```sh
   sudo snap logs -f sdk-cpp-provider-simple
   ```

3. Confirm input/result log lines appear approximately every second even when
   no client is reading the node.
4. Browse `sdk/cpp/datalayer/provider/simple` and confirm the original four
   nodes remain alongside `sqrt`.
5. Read `sqrt` without supplying an input argument. Confirm it returns a
   `float32` value from `0.0` to `100.0`.
6. Refresh the read to observe periodic updates. Consecutive random values can
   repeat, so a repeated result alone does not indicate a failure.
7. Confirm metadata marks the node read-only and that writing is not allowed.

No real or virtual ctrlX device was modified or used to validate these changes
during this exercise.

## 18. Final behavior summary

```text
Application startup
  -> Connect to the existing Data Layer broker
  -> Construct SquareRootNode
       -> Generate and log the first random input and square root
  -> Register the new sqrt node and the original sample nodes
  -> Enter the existing connection-monitoring loop
       -> Wait approximately one second
       -> Generate a random input
       -> Calculate and atomically store its square root
       -> Log the input and result
       -> Repeat while connected and not shutting down

Data Layer read of sqrt
  -> Return the latest stored float32 result
  -> Do not require an input argument
  -> Do not generate a new value

Application shutdown
  -> Unregister sqrt along with the original nodes
  -> Stop and delete the provider
  -> Stop the Data Layer system
```

The exercise therefore adds autonomous random-value calculation to the original
provider sample while preserving the sample's existing Data Layer nodes and
packaging structure.
