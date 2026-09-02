# Speedtest

Measures this connection with `networkQuality`, the tool macOS already ships, and keeps every
reading so the next one can be read against this network's own past rather than against a
number from a review. Capacity is only half of what it reports. The other half is
responsiveness under load, the RPM figure, which is what decides whether a call stutters and a
page feels slow, and it is the reason this tool was chosen over the usual ones.

A run takes about ten seconds and draws itself while it goes. The tool decides whether to
report progress by asking whether its output is a terminal, so it is run under one, and it then
prints a downlink figure, an uplink figure and a responsiveness figure about four times a
second. Those figures are the live graph, and every finished run keeps its own shape, so a
reading is never a bare number even when it is the only one this network has. The final numbers
are still the tool's own machine readable answer rather than the last live sample, since that
answer carries twenty seven fields where the progress line carries three.

The run belongs to the plugin rather than to the window, so closing the list does not stop it
and the result lands in the history either way.

History is kept per network and capped by count, fifty runs each by default, with nothing ever
expiring by age. A reading from months ago is the most useful record in the file the day
something changes. Networks are identified by something that needs no permission, so the
separation is always correct even when macOS refuses to say what a network is called.

## Opening it

Through the launcher, by its own row or by typing `st` or `speed` and a space to scope the
launcher to its rows. There is no key of its own, since a speedtest is something reached for
when the network feels wrong rather than something used daily.

## In the list

Return runs a test without leaving the row, and Return on Stop ends one in flight. Return on a
past reading copies a one line summary of it. Return on Settings or Other networks opens that
level and Backspace on an empty field steps back out of it. The pane on the right follows the
highlight throughout and scrolls under the trackpad when it holds more than fits.

Through the alias the list is smaller on purpose. The launcher reserves no companion pane and
nothing can be pushed onto its list, so the pane and the settings level cannot exist there. What
the alias carries is taking a reading and seeing the past ones, and a row at the top that opens
the tool proper. Starting a run from the alias opens it too, since a row in the launcher has
nothing that would redraw it and a run worth watching should be watchable.

## Two kinds of graph, and why they are not the same

A curve is drawn for a continuous sample, throughput through one run or latency through one
load, where the space between two points is elapsed time and joining them tells the truth. Bars
are drawn for a series of separate runs, where the space between two of them is however long
the person went without measuring, and a line joining those would draw a slope through a gap it
knows nothing about. A network with one reading is therefore shown that reading's own shape
rather than a trend, since a trend of one is flat by construction and says nothing.

## What it deliberately does not do

There is no announcement when a run finishes with the list closed. The result lands in the
history and appears the next time the list opens. A small card saying so would be the right
answer and it needs a CanvasPanel grant this plugin does not have, so the honest position for
now is silence rather than an alert, which is reserved in this configuration for a failure that
stopped an action outright.

There is no absolute capacity number here. The default run measures one direction at a time, so
a capacity figure reads close to this line's ceiling and is comparable to a number from any other
test of the same connection. `networkQuality` still talks to whichever Apple CDN edge DNS hands
it and cannot be pointed anywhere else, so it remains the wrong tool for arguing with an ISP. A
setting measures both directions at once instead, which is what real use looks like and reads
lower on purpose.
