# README datalayer.provider.simple

## Introduction

This sample app creates a new __ctrlX Data Layer__ folder 'sdk/cpp/datalayer/provider/simple/' with nodes of different datatypes.

## Functional Description

It demonstrates how you can create __ctrlX Data Layer__ nodes with different data types.
These nodes can be accessed by any __ctrlX Data Layer__ client app.
The metadata of the nodes are provides by a metadata database.

The read-only `sdk/cpp/datalayer/provider/simple/sqrt` node exposes a `float32`
square-root result. The app generates a random input from `0.00` to `10000.00`
(inclusive, in steps of `0.01`) at startup and approximately every second while
connected. Each input and its square root are logged, without requiring a client
request. Reading the node returns the latest result and requires no input argument;
it does not trigger another calculation. Results range from `0.0` to `100.0`.
The square-root node supplies its metadata programmatically.

## Implementation Description

All actions are implemented in main.cpp:

* Start __ctrlX Data Layer__ system
* Connect as __ctrlX Data Layer__ provider
* Register a flatbuffers schema
* Register metadata database
* Register several __ctrlX Data Layer__ nodes: sdk/cpp/datalayer/provider/simple/
* Endless loop where the __ctrlX Data Layer__ connection is observed
* Shutdown if the __ctrlX Data Layer__ connection is broken

!!! important
    If the app is running as snap on a ctrlX CORE it will be restarted if it has exited on error.

___

## License

SPDX-FileCopyrightText: Bosch Rexroth AG

SPDX-License-Identifier: MIT
