#!/usr/bin/env bash
# lf in the directory the calling pane sits in, which is where the floating pane starts. Every
# lf key works here, since lf runs its pickers in its own terminal and needs no multiplexer.
exec lf
