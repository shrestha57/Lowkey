# Lowkey 🤫

**Plans that fit everyone's wallet.** Friends secretly tap what they can spend, and Lowkey finds real nearby spots the whole group can afford. Nobody has to say they're broke.

**Try it:** https://shrestha57.github.io/Lowkey/

## How it works
1. Start a plan: your name, an area (or your location) and how far people will go.
2. Share the invite link in your group chat.
3. Everyone opens it on their own phone and privately picks a budget.
4. See free hangouts, coffee, cheap eats, activities and more, filtered to the group's lowest budget.
5. Optional private "stretch" vote to go one level higher. Nobody knows who said no.

Budgets are private by design: the database only ever returns the group's combined level, never anyone's individual answer.

## Built with
- Plain HTML, CSS and JavaScript (single file, no build step)
- Budgets from $0 to $500 (slider or typed); the group number is rounded down to the nearest $5
- [Supabase](https://supabase.com) free plan for shared plans (setup: `supabase-setup.sql`)
- [OpenStreetMap](https://www.openstreetmap.org/copyright) data via Overpass and Nominatim (free, no API key)
- [Leaflet](https://leafletjs.com/) for the map

Prices are rough per-person estimates by type of place. This is an early prototype: feedback welcome!
