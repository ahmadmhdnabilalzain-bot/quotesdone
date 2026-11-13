// drawing_vocabulary — THE WORDS A DRAWING IS MADE OF: the trade's own vocabulary and the short codes a supplier
// reads on a plan. One file, read by cad_identity.ts (which layer / block words survive; which title-block text is
// a party rather than a view title) and drawing_text_policy.ts (which words of a drawing may reach a supplier).
// 25 Sep 2026, sales_engineer. It imports nothing, so both of those can use it without importing each other.
//
// A word NOT here is withheld from a supplier's page (drawing_text_policy, fail closed). Adding a word here is
// therefore a decision that the word names what is drawn and never who it is for: rooms, elements, devices,
// finishes, units, and the small words notes are written in. A name that is also a trade word ("NORTH GATE")
// passes the vocabulary, and is caught only when it is the customer's own seed or sits in a title block.

/** CAD layer / block vocabulary: AIA CAD Layer Guidelines groups, ISO 13567 element words, trades and devices. */
export const VOCAB = new Set(`
  wall walls door doors glaz glazing wind window windows flor floor floors clng ceiling ceilings roof roofs
  strs stair stairs ramp elev elevator lift lifts furn furniture fixt fixture fixtures eqpm equip equipment
  duct ducts ductwork pipe pipes piping hvac plmb plumbing fire sprk spkl sprinkler sprinklers elec electrical
  lite light lights lighting powr power comm communication data tele anno note notes text symb symbol symbols
  iden iden patt hatch grid dims dimension dimensions case casework cols column columns beam beams slab slabs
  fndn foundation footing conc concrete steel stl masonry block brick tile tiles paving pave site topo cont
  road curb kerb park parking land landscape plnt plant plants tree trees irrg irrigation fenc fence gate gates
  supp supply retn return exhs exhaust exh diff diffuser diffusers grille grilles grilles regs register louv louver
  louvre damp damper dampers vav fcu ahu fan fans pump pumps valve valves boiler chiller chillers tank tanks
  cool cooling heat heating vent ventilation drain drains drainage sani sanitary sewr sewer storm strm dome
  domestic cold hot water gas medg medical oxygen vacuum cond condensate refr refrigerant
  smoke detector detectors alarm alarms bell bells horn strobe sounder beacon call point panel panels mcp fap
  socket sockets outlet outlets switch switches recp receptacle cable cables tray trays trunking conduit
  ladder busbar busway meter meters db dbs mdb smdb board boards lum luminaire luminaires emergency exit
  cctv camera cameras access control speaker speakers pa bms tv sat
  toilet toilets wc basin basins sink sinks shower showers bath bathtub urinal urinals tap taps mixer heater
  kitchen pantry counter cabinet cabinets wardrobe bed beds sofa table tables chair chairs desk desks
  villa room rooms area areas zone zones level levels ground first second third mezz mezzanine basement
  new existing demo demolition remove removed proposed future temp typical typ
  outline outlines boundary plot interior exterior int ext main sub north south east west
  insulation cladding facade curtain partition partitions gypsum board paint finish finishes skirting
  marble granite porcelain ceramic carpet vinyl wood timber aluminium aluminum glass handrail railing balustrade
  pool pools swim swimming spa jacuzzi lift lifts shaft escal escalator scaf scaff scaffold scaffolding turf lawn grass
  soft softscape hard hardscape shrub groundcover rack racks racking waterproofing wprf membrane screed purlin purlins
  bracing rafter rafters girt girts joist joists stl curb edging gutter coping flashing drip irr trunk cndt chw chws chwr
  hhw spkl hydr hydrant hose kitchen kex kexh tfa fresh space spce ceil clg sign signage totem
`.split(/\s+/).filter(Boolean));

// The words of a drawing's text beyond layer names: rooms, drawing furniture, devices, finishes, and the small
// words notes and instructions are written in. Second review of #967 (25 Sep 2026) measured 18 of 49 ordinary
// labels withheld (SHOWER, VANITY, POWDER ROOM, SWIMMING POOL, "REFER TO MEP SPECIFICATION", "EXISTING WALL TO BE
// DEMOLISHED" ...); those and their neighbours are here.
const TRADE = `
  a an the of to at in on by for and or with from as per not no all any each every only other same see refer note notes
  is are be been shall must should will may can do does if where when unless until prior before after during via into
  onto off up down out within without between through
  general typical typ unless otherwise stated shown indicated noted mounted installed provide provided fixed mount
  above below over under between near top bottom side left right front back center centre high low level levels
  new existing remove relocate retain future proposed approx approximately min max minimum maximum
  office meeting room store storage lobby reception corridor hall hallway kitchen pantry toilet toilets bathroom bath
  bedroom master guest living dining majlis maid maids laundry utility electrical mechanical plant riser shaft stair
  stairs staircase lift lifts balcony terrace roof garage parking entrance exit foyer dressing closet study library
  gym pool prayer server it telecom janitor cleaner lounge waiting conference board boardroom open plan area zone
  plan section elevation detail details schedule legend key scale drawing sheet layout ground first second third
  fourth fifth floor floors basement mezzanine podium typical north south east west part
  smoke heat detector detectors sounder beacon strobe call point panel socket sockets outlet outlets double single
  twin switch switches isolator fused spur light lighting luminaire downlight emergency exit sign fan coil unit units
  supply return exhaust extract fresh air grille diffuser damper duct ducts pipe pipes valve drain gully trap sprinkler
  hose reel extinguisher cabinet data telephone tv cctv camera access card reader speaker intercom meter distribution
  board db mdb smdb cable tray trunking conduit containment earth bonding lightning protection
  wall walls door doors window windows glazing partition ceiling floor finish tile tiles paint skirting column columns
  beam slab opening void dim dimension dimensions height width length depth thickness dia diameter radius
  mm cm m sqm kw kva amp amps volt volts watt watts lux cfm lps nos no qty quantity each set lot
  affl ffl ssl fcl tos bos cl sfl rl fgl ngl datum
  shower showers vanity vanities powder walk walkin wc wcs ensuite suite family sitting salon hall drawing
  swimming jacuzzi sauna steam spa deck pergola gazebo fountain lawn planter courtyard garden landscape outdoor
  indoor driveway drive ramp boundary compound guard guardhouse security gatehouse servant servants quarter quarters
  driver drivers staff male female ladies gents men women disabled accessible baby changing nursery kids children
  playroom cinema theatre theater media games bar cafe cafeteria canteen restaurant retail shop showroom warehouse
  workshop loading bay store stores archive copy print visitor visitors family maid laundry ironing linen
  generator transformer substation switchgear switchboard rmu lv mv hv ups inverter battery batteries solar charger
  booster pump pumps heater heaters tank tanks water hood cooker hob oven fridge refrigerator freezer dishwasher
  washer dryer microwave island shelf shelves shelving rack racks counter worktop splashback
  waterproofing waterproof membrane screed plaster plastering render rendering false suspended raised access
  blockwork brickwork masonry stonework joinery ironmongery glazed louvred louvered frameless sliding folding
  hinged swing pivot fire rated smoke seal seals threshold sill lintel coping parapet canopy awning shade skylight
  flooring floors cladding facade tiling marble granite porcelain ceramic mosaic carpet vinyl parquet laminate
  wood wooden timber veneer gypsum cornice moulding molding skirting paint painted emulsion enamel epoxy
  push button bell doorbell buzzer chime split cassette ducted package window thermostat sensor sensors occupancy
  motion daylight dimmer dimmable timer contactor relay breaker breakers mcb mccb rcd rcbo elcb acb ats isolator
  earthing lightning arrester surge fuse fuses way ways pole poles phase single three neutral live
  specification specifications spec specs drawings drawing reference references manufacturer manufacturers
  recommendation recommendations requirement requirements required require requires standard standards code codes
  regulation regulations authority authorities local approval compliance comply accordance according
  verify confirm coordinate coordinated coordination site works work installation install installed fix fixing
  fixings demolish demolished demolition retained removed relocated replaced replace extend extended extension
  connect connected connection connections match matching similar equal equivalent tested testing commissioning
  size sizes sized sqmm core cores armoured armored copper aluminium conductor conductors run runs route routing
  depth buried trench sleeve sleeves duct ducts chamber chambers manhole manholes inspection access cover covers
  grating gratings channel channels gutter gutters downpipe downpipes rainwater soil waste vent stack stacks
  cold hot mixed domestic potable irrigation fire fighting hydrant hydrants landing valve riser risers wet dry
  foam gas suppression fm system systems panel panels repeater mimic zone zones loop loops address addressable
  conventional detector detectors beam optical ionisation multi sensor heat rate rise fixed temperature
  speaker speakers public address voice evacuation paging background music amplifier
  data voice network telephone socket outlet rj cat fibre fiber optic patch rack cabinet wifi access point
  camera dome bullet ptz nvr dvr monitor monitors intercom video audio door entry card reader lock locks maglock
  exit release break glass emergency stop call nurse
  north arrow true grid gridline gridlines axis axes centre centerline centreline line lines hidden dashed
  existing proposed future phase stage temporary permanent
  new old typical similar opposite hand mirror mirrored
  approx nominal overall internal external clear finished structural setting out
  tbc tbd nts nic ofci na
  mep xlpe swa upvc cpvc hdpe lszh ppr pex ahu fahu fcu vrf vrv
  shallow deep end ends tag tags description descriptions circulation duty standby sand filter filters filtration
  chlorinator chlorination salt underwater led skimmer skimmers wide mouth anti vortex inlet inlets outlet coping
  travertine bullnose edge edges cementitious crystalline coat coats pu pipework suction balance overflow equipotential
  colour color blue white grey gray black mix raft blinding rc layer layers reinforcement rebar bars bar cover lap
  invert soffit freeboard turnover backwash dosing ozone uv ph chlorine heat exchanger plantroom nozzle nozzles
  wall walls floor bench benches step steps ledge sump gutter grating gratings overflow tile shotcrete gunite
  dubai sharjah ajman fujairah uae
`;
// LEVELS AND POOL WORDS (13 Nov 2026, sales_engineer; anonymity audit B, finding L4). The CAD preview of the auditor's
// pool DXF withheld "SHALLOW END FFL -1.20" and "DEEP END FFL -1.80", and the policy withheld every line of the B1
// equipment schedule and general notes ("CIRCULATION PUMP 1.5 HP 230V", "MAIN DRAIN ANTI-VORTEX", "2. COPING:
// TRAVERTINE 600x300x30 MM"): levels and pool equipment a contractor prices from. They are the trade's words, added
// above; the emirate alone may cross (founder ruling 1683), so the four single-word emirates are here too.

/** The short codes a plan prints: devices, disciplines, units, levels. A word of 1-3 letters passes only if it is
 *  here or is itself a short trade word above (bed, fan, air, via); any other short word ("DAR", "WSP", "ORB") is
 *  withheld (second review of #967: every word of 3 letters or fewer used to pass). */
export const CODES = new Set(`
  a an the of to at in on by for and or as per no not all any see it is be if up
  db dbs mdb smdb sdb emdb fdb ldb pdb mcc
  fcu ahu fahu vav cav fcv ef sf tf kef ac vrf vrv cu du tr btu cfm lps rpm hp kw kva kwh va v w a ma hz ph
  sd hd md mcp fap fa fe fh fhc fhr hr fb ms mcb acb rcd sw sk skt dskt ssk tsk fs fsw so dso
  dl el em eml exl ext exit rl ll pl bl wl ld sl cl tl
  ups ats bms cctv pa tv sat ip nvr dvr cat rj utp ftp stp sfp lan wan av
  mm cm m km mt sqm sqmm dia thk typ tbc tbd nts nic min max no nos qty ea pcs set lot
  ffl sfl ssl affl fcl fgl ngl tos bos rl gl cl el up dn
  wl twl swl hwl lwl toc tow bow il inv cop sop fl tol
  uwl md ri sk mh ic rc pn ip led uv g h
  gf ff sf rf lg ug mz mez bf bsmt pod
  wc wcs bed liv din kit str st bth ens gym lob rec wt ht lt gt
  pvc upvc cpvc hdpe ppr gi ms ss cu al xlpe swa lszh pe pex abs
  lv mv hv ac dc tpn spn tp sp dp np mep
  x
`.split(/\s+/).filter(Boolean));

const WORDS = new Set([...VOCAB, ...TRADE.split(/\s+/).filter(Boolean)].map((w) => w.toLowerCase()));

/** A word of the trade: in the vocabulary as written, or once a plural S / ES is folded. */
export function tradeWord(w: string): boolean {
  const l = String(w || '').toLowerCase();
  if (!l) return false;
  if (l.length <= 3) return CODES.has(l) || WORDS.has(l);
  return WORDS.has(l) || WORDS.has(l.replace(/es$/, '')) || WORDS.has(l.replace(/s$/, ''));
}

/** Every word of `text` is the trade's (and it has at least one): a view title, a room, a device, a note. */
export function tradeOnly(text: string): boolean {
  const toks = String(text || '').split(/[^A-Za-z]+/).filter(Boolean);
  return toks.length > 0 && toks.every(tradeWord);
}
