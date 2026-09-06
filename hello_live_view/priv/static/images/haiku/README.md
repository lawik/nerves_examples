# Haiku OS icon theme

The SVGs in this directory come from the **Haiku OS Icon Theme** by lxmx:

<https://github.com/lxmx/haiku-icons>

Licensed under the MIT/X Consortium License — see `LICENSE` next to this file.
Upstream credits the work of Untouchable89, phillbush and the Haiku OS
developers. Please support the OS and give it a try.

Only the icons this app actually renders were vendored here, to keep the Nerves
firmware small: upstream ships ~2,300 icons at 15 MB, this directory is ~140 KB.
To add more, clone the repo above and copy what you need out of its `svg/`
directory (follow symlinks — some entries point into `svg-extra/`):

    cp -L haiku-icons/svg/utilities-terminal.svg priv/static/images/haiku/

Everything under `priv/static/images/` is served by `Plug.Static`, so these two
text files are public too. They are a few hundred bytes and keep the attribution
travelling with the artwork, which the license requires.
