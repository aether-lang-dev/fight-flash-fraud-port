Fight Flash Fraud, Ported to Aether
===================================

This repository is an Aether port of F3, Fight Flash Fraud. It tests
flash media by writing deterministic ``.h2w`` files and reading them back
to verify that the device really stores the capacity it claims.

The active ``main`` branch is Aether-only. The upstream C implementation
is preserved on the ``original_c_code`` branch for reference and history.


What is here
============

- ``src/f3.ae``: single CLI entrypoint with ``write`` and ``read`` subcommands.
- ``src/f3core/module.ae``: shared F3 write/read verification logic.
- ``app/fight_flash_fraud.ae``: Aether UI app using ``aether-ui``.
- ``tests/``: ``std.spec`` unit tests and an AetherUIDriver UI test.
- ``bootstrap.sh``: convenience bootstrap for the toolchain and sibling checkout.
- ``AETHER_PIN`` / ``AETHER_FETCH``: the Aether version floor, and the
  release to install when that floor is not met.


Build
=====

The normal build expects ``ae`` and ``aetherc`` on ``PATH``. To get set up
from scratch, run:

::

    ./bootstrap.sh

That installs the Aether toolchain if the one on ``PATH`` is older than
``AETHER_PIN``, clones ``~/scm/AetherThings/aether-ui`` if missing, then
builds the app and runs the tests.

The two dependencies use deliberately different mechanisms. Aether is a
*released toolchain*, installed to ``~/.local`` by its own remote
installer — no clone and no build-from-source. ``aether-ui`` has to be a
*source checkout*, because ``scripts/build-ui.sh`` compiles its backend C
(``aether_ui_gtk4.c`` and friends) directly and ``scripts/test-ui.sh``
puts ``tests/lib/uidriver.ae`` on the module path.


Aether version
==============

Two files, on two different clocks:

``AETHER_PIN``
    A *floor*: the oldest Aether that can build this repo, currently
    ``0.538.0`` — the release where ``std.spec`` entered the stdlib. It
    moves only when the code starts calling a primitive an older Aether
    lacks, in the same commit that introduces the call. If your ``ae`` is
    already above it, ``bootstrap.sh`` leaves it alone.

``AETHER_FETCH``
    The known-good release to *install* when the floor is not met,
    currently ``0.542.0``. It must be ``>=`` the pin, and it moves for
    reasons unrelated to language features — toolchain portability, a
    fixed codegen bug. A newer number is not automatically better; it is
    another thing to have tested.

There is no longer an ``aeocha`` dependency. That framework's BDD core was
absorbed into the Aether stdlib as ``std.spec`` (0.538.0) and its
mutation-testing driver as ``std.mutation`` (0.540.0), and the standalone
repo is retired. The specs import ``std.spec``, which ships inside the
toolchain, so nothing clones it and nothing needs ``$AEOCHA_DIR``.

To build manually:

::

    make
    make app

The outputs are:

- ``build/f3``
- ``build/fight_flash_fraud``


CLI
===

Write a test pattern to a mounted flash filesystem:

::

    build/f3 write --start-at=1 --end-at=32 --size-mb=1024 /media/$USER/FLASH

Read and verify the files:

::

    build/f3 read --start-at=1 --end-at=32 /media/$USER/FLASH

For a small simulation:

::

    mkdir -p /tmp/f3-aether-ui
    build/f3 write --start-at=1 --end-at=1 --size-mb=1 /tmp/f3-aether-ui
    build/f3 read --start-at=1 --end-at=1 /tmp/f3-aether-ui


UI App
======

Build and launch:

::

    make app
    ./build/fight_flash_fraud

The UI offers:

- path selection for flash-like mounted block devices
- write progress as a proportional grid
- read/verify results as check/cross grid cells
- a human result such as ``Flash size is correct for tested 1MB. No fraud detected.``
- hidden detailed log via ``Show log``


Tests
=====

Run all tests:

::

    make test

The test suite includes:

- ``std.spec`` unit coverage for app-facing text/verdict helpers.
- AetherUIDriver coverage for the UI: initial disabled read button, write,
  read enablement, grid update, and no-fraud verdict.

On Linux, ``scripts/test-ui.sh`` tries the real display first. If the
AetherUIDriver endpoint does not come up, it falls back to ``xvfb-run`` when
available. To force the real display path:

::

    F3_UI_NO_XVFB=1 make test-ui


Branch Layout
=============

``main``
    Aether port. This is the active branch for development and publishing.

``original_c_code``
    Untouched upstream F3 C snapshot. Use this as the historical link to the
    original implementation; do not mix Aether port commits into it.


License
=======

This port keeps the upstream F3 license. See ``LICENSE``.
