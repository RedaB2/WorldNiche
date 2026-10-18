# Natural Earth geometry

Made with Natural Earth.

The globe uses **Natural Earth 1:50m Admin 0 Countries** data, downloaded on October 17, 2026 from the [maintainer’s repository](https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_50m_admin_0_countries.geojson). Natural Earth’s [terms of use](https://www.naturalearthdata.com/about/terms-of-use/) place its raster and vector map data in the public domain.

The bundled `WorldNiche/Resources/GlobeCountries.geojson` keeps geographic geometry and the identifiers needed by the app, rounds coordinates to four decimal places, and normalizes country selection identifiers. Somaliland maps to Somalia and Northern Cyprus to Cyprus for the app catalog. Geographic features without a catalog identity can still be drawn. Natural Earth’s default boundary representation is retained; the map is an educational display, not a boundary adjudication.

Credit: Natural Earth contributors, including Tom Patterson and Nathaniel Vaughn Kelso.
