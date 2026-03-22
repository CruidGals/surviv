### routing

Implemented in `Services/SafeRouteEngine.swift`. Uses on-device A* over an
OSM road graph with danger-zone cost inflation — no server required.

OSM data lives in `Resources/mapUva.osm` (UVA campus area).