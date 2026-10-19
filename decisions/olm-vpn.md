# Olm VPN, one contract over adapters

Status. VPN providers are adapters behind one contract. A location is one shape for every
adapter, and an adapter's own vocabulary reaches the shared layer only as the subtitle it
declares and the search terms it declares.

## Now

A location carries `id`, `label`, `detail`, `countryCode`, `cityCode` and `terms`, with `country`
and `city` optional. `detail` is the row subtitle in the adapter's own spelling, `cityCode` is the
adapter's own key for the city and opaque to the plugin, and `terms` is a list of strings the place
also answers to, mandatory even when empty. `contract.validateLocation` and `validateLocations`
check the shape. When a listing lands, an entry that breaks it refuses the whole listing with one
console line naming the provider and the gap, and the page shows its waiting row. The row builder
reads only the contract, the title from `label`, the subtitle from `detail`, the search text from
`label` and the names from `terms`. Mullvad declares its city code then its country code, IVPN its
gateway host then its country code. The plugin AGENTS.md says the same for a new adapter's author.

## Rejected

A city code keyword added in the shared row builder. Rejected 2026-10-19. It reads one backend's
vocabulary into every other, which is the special case the contract exists to prevent.

Terms as keywords rather than names. Rejected 2026-10-19. A code spelled whole should lead the list
the way an emoji shortcode does. Measured on the real relay list of 91 cities through the shared
engine, tia as a keyword listed Tirana third after Santiago and Zagreb, and as a name it lists
Tirana first.

The country code assumed by the builder. Rejected 2026-10-19. It was a quiet assumption that every
backend has a country code worth typing, and it is replaced by each adapter declaring its country
code among its terms, so al still finds Tirana.

## Log

### 2026-10-19 14:38

The rule was stated that providers are adapters behind one contract and the shared layer holds no
special case for any provider. The row builder had spelled Mullvad's vocabulary as the subtitle
fallback, assumed the country code was a search word, and set no terms, so Mullvad's city code tia
and IVPN's gateway us-ca-sjc were shown and never searchable. The location shape above was
settled with the person, who chose names over keywords and chose that each adapter declares its
country code among its terms.

The measurement, a typed query and the rows it listed before and after the code was added as a
further name, on the real Mullvad relay list through the shared engine.

| Query | Before | After |
| --- | --- | --- |
| tia | Santiago, Zagreb | Tirana first |
| nyc | nothing | New York |
| zrh | nothing | Zurich |
| ams | Amsterdam | unchanged |
| fra | Frankfurt, Paris, Bordeaux | unchanged |
| sto | Stockholm, Boston, Tallinn | unchanged |
| al | Tirana, McAllen | unchanged |

Decided that the contract gains `validateLocation` and `validateLocations`, that a listing breaking
the shape is refused whole, and that `detail` and `terms` are required.
