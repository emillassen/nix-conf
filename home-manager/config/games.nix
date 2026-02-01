{
  lib,
  pkgs,
  ...
}:
{
  home.packages =
    with pkgs;
    lib.mkAfter [
      wesnoth # Battle for Wesnoth, a free, turn-based strategy game with a fantasy theme
      #openra # Open Source real-time strategy game engine for early Westwood games such as Command & Conquer: Red Alert
      #openrct2 # Open source re-implementation of RollerCoaster Tycoon 2 (original game required)
      #openttd # Open source clone of the Microprose game "Transport Tycoon Deluxe"
      #xonotic # Free fast-paced first-person shooter
      #freeciv # Multiplayer (or single player), turn-based strategy game
      #pioneer # Space adventure game set in the Milky Way galaxy at the turn of the 31st century
      #zeroad-unwrapped # Free, open-source game of ancient warfare
      #endless-sky # Sandbox-style space exploration game similar to Elite, Escape Velocity, or Star Control
      #widelands # Widelands is a free, open source real-time strategy game with singleplayer campaigns and a multiplayer mode. The game was inspired by Settlers II
      fheroes2 # A recreation of Heroes of Might and Magic II game engine. Run `nix-shell -p innoextract` then `innoextract setup.exe` from GOG and then `mv DATA MAPS MUSIC SOUND HEROES2/ANIM ~/.local/share/fheroes2`
    ];
}
