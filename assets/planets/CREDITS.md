# Planet maps

Global surface maps of Jupiter, Europa, Io, Ganymede and Callisto from
NASA's 3D Resources collection (https://github.com/nasa/NASA-3D-Resources,
"Images and Textures"), originally from Voyager/Galileo mosaics. NASA imagery
is public domain.

Prepared for the game: Jupiter and Io resampled to 1024x512 (Io's missing
polar wedges filled by diffusion); Europa, Ganymede and Callisto kept as
greyscale detail maps that `shaders/planet.gdshader` tints (Callisto's
no-data gaps filled and re-grained).
