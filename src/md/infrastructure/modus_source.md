# The source of modus

The viewer compiles packages of the modus repository into itself. It does not copy them.

## The path

- The flake has the input `modus`: the modus repository, with no flake of its own (`flake = false`). `flake.lock` pins
  its commit.
- The development shell sets `MODUS_SOURCE` to that source. The tool gives `-collection:modus=$MODUS_SOURCE/src/library`
  to each odin command, so the sources import `modus:contract/...` and `modus:support/...` as the system does.
- The package build of the flake sets the same variable.
- To build against a local checkout of modus, set `MODUS_SOURCE` to its root. The tool stops with a sentence when the
  variable is empty.

## The packages that the viewer imports

| Package | Why |
|---|---|
| `modus:contract/remote_display` | The records, their borders and the screen piece coder |
| `modus:contract/errors` | The error record of the QUIC calls |
| `modus:support/quic` | QUIC with TLS 1.3, mutual, with raw public keys |
| `modus:support/random` | The random generator of a QUIC connection |
| `modus:private/cryptography/cryptography_primitives` | The cryptography module compiled for the host: the procedures of `quic.Cryptography` |

## What builds on a host

- **Linux, x86-64.** All of them. The tool of modus builds the same packages in its peer
  (`tools/modustool/machine/peer_remote_display.odin`).
- **Windows, x86-64.** Expected, not yet built. The packages call no system of the host.
- **macOS and other ARM64 hosts.** Not now. `modus:support/random/entropy.odin` reads the generator of the processor
  with x86 instructions (`rdrand`, `rdseed`, `cpuid`), with no file for another processor.

## The package that calls the kernel

`modus:support/random` imports `modus:support/system`, which declares the entries of the kernel as foreign
procedures (`system_enter`, `thread_record`). On a host, `modus:support/system/kernel_entry_on_the_host.odin`
(`#+build !freestanding`) gives the linker those two names. Each one stops the program at once, because no host path
must reach the kernel. The viewer never calls them: it seeds its generator with `random.generator_seed` from the
generator of the host system (`core:crypto`), and never with `random.generator_from_context`. No replacement is
needed in the viewer.

## The refused forms

- **A copy of the packages in this repository.** Two copies of the protocol drift. The pin of the flake is one
  version of the protocol for both sides.
- **A git submodule of modus.** The repository of modus is large, and the viewer reads one folder of it. The flake
  input gives the same pin with no checkout in the tree.
