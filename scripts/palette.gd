class_name Palette
extends RefCounted
## Palette centrale du jeu. Uniquement des constantes.
## v2 (refonte HUD triple-A) : passage FROID bleu-gris -> CHARBON CHAUD + bronze/or.
## Le code couleur du doc : vert=prod/allié/entrée, rouge=danger/ennemi/sortie,
## or=ressources, bleu=magie.

# --- fond / monde ---
const GROUND      := Color(0.055, 0.047, 0.041)   ## vide de l'appli, derriere tout
const BG          := GROUND
const GROUND_A    := Color(0.121, 0.110, 0.098)
const GROUND_B    := Color(0.102, 0.092, 0.081)
const FARM_ZONE   := Color(0.150, 0.160, 0.098)
const BUILD_EDGE  := Color(0.55, 0.42, 0.20, 0.18)
const GRID        := Color(1, 1, 1, 0.04)
const DIVIDER     := Color(0.44, 0.60, 0.32)

# --- surfaces (charbon chaud, 3 niveaux + creux) ---
const PANEL       := Color(0.098, 0.086, 0.075, 0.97)
const PANEL_BG    := PANEL
const PANEL_RAISED := Color(0.129, 0.113, 0.098)
const WELL        := Color(0.048, 0.041, 0.035)

# --- cadre / bevel ---
const BORDER_DIM        := Color(0.212, 0.180, 0.145)
const BORDER_BRONZE     := Color(0.451, 0.333, 0.180)
const BORDER_BRONZE_LIT := Color(0.596, 0.451, 0.263)
const BORDER_GOLD       := Color(0.831, 0.643, 0.302)
const BEVEL_HI          := Color(1.000, 0.980, 0.920, 0.07)
const BEVEL_LO          := Color(0.000, 0.000, 0.000, 0.42)
const INK                := Color(0.055, 0.045, 0.035)
const SHADOW      := Color(0, 0, 0, 0.30)

# --- portails / chemin ---
const SPAWN       := Color(0.878, 0.341, 0.290)
const KING        := Color(0.906, 0.702, 0.318)
const PATH_HINT   := Color(0.62, 0.70, 0.85, 0.30)

# --- texte ---
const TEXT        := Color(0.878, 0.847, 0.788)
const TEXT_DIM    := Color(0.588, 0.541, 0.478)
const TEXT_MUTE   := Color(0.427, 0.388, 0.337)
const TEXT_TITLE  := Color(0.906, 0.749, 0.408)
const GOLD_TEXT   := TEXT_TITLE
const DANGER_TEXT := Color(0.855, 0.388, 0.318)

# --- accents (code couleur du doc) ---
const ACCENT_GREEN     := Color(0.408, 0.671, 0.325)
const ACCENT_GREEN_LIT := Color(0.545, 0.796, 0.435)
const ACCENT_RED       := Color(0.741, 0.235, 0.196)
const ACCENT_RED_LIT   := Color(0.855, 0.361, 0.298)
const ACCENT_GOLD      := Color(0.906, 0.702, 0.318)
const ACCENT_BLUE      := Color(0.353, 0.588, 0.741)
const ACCENT_AMBER     := Color(0.902, 0.545, 0.235)

# --- barres ---
const TRACK_DARK  := Color(0.035, 0.030, 0.026)
const FILL_GREEN  := Color(0.404, 0.686, 0.324)
const FILL_RED    := Color(0.706, 0.184, 0.153)
const FILL_GOLD   := Color(0.851, 0.647, 0.275)
const HP_GOOD     := FILL_GREEN
const HP_LOW      := Color(0.851, 0.600, 0.180)
const HP_RED_HI   := Color(0.855, 0.361, 0.298)
const HP_BG       := Color(0, 0, 0, 0.55)

# --- unites / monde ---
const TOWER       := Color(0.60, 0.58, 0.54)
const TOWER_BASE  := Color(0.16, 0.14, 0.12)
const FIGHTER     := Color(0.408, 0.671, 0.325)
const ENEMY       := Color(0.741, 0.235, 0.196)
const PEON        := Color(0.882, 0.700, 0.320)

# --- boutons ---
const BTN          := Color(0.152, 0.133, 0.113)
const BTN_HOVER    := Color(0.205, 0.180, 0.150)
const BTN_PRESS    := Color(0.105, 0.088, 0.072)
const BTN_OFF      := Color(0.082, 0.072, 0.062)
const BTN_GREEN     := Color(0.267, 0.427, 0.227)
const BTN_GREEN_HI  := Color(0.325, 0.518, 0.271)
const BTN_GREEN_DEEP:= Color(0.161, 0.271, 0.149)
const BTN_GREEN_RIM := Color(0.451, 0.616, 0.318)
const BTN_DANGER      := Color(0.483, 0.140, 0.121)
const BTN_DANGER_HI   := Color(0.585, 0.181, 0.156)
const BTN_DANGER_DEEP := Color(0.331, 0.092, 0.082)
const BTN_DANGER_RIM  := Color(0.639, 0.310, 0.180)

# --- ambiance (compat) ---
const KEY_WARM     := Color(1.0, 0.80, 0.46)
