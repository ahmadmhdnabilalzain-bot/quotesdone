// identity_keeps_trade_text.fixtures.ts — 421 legitimate quoting sentences (EN + AR) that must cross every scrubber UNCHANGED,
// written by the independent review of the anonymity fix round (13 Nov 2026, scratchpad rv/corpus.ts) and adopted as a permanent
// corpus. A row ending '#arguable' names a place a reviewer could read either way; the test says what it does with each.
export const EN: string[] = [
  // brands / products holding place words
  'Marina blue emulsion 2 coats', 'Jumeirah series mixer chrome', 'Sharjah Cement OPC 50 kg bags', 'Al Ain water 500 ml cartons', 'RAK Ceramics floor tile 600x600',
  'Dubai Cable (Ducab) 4C x 16 sqmm XLPE', 'Emirates Steel rebar B500B', 'Gulf Extrusions aluminium profile', 'Deira blue tiles 300x300', 'Masafi water dispenser',
  'Liwa sand colour paver 80 mm', 'Union Cement SRC', 'Ducab cable 3C x 2.5', 'Jotun Fenomastic in Marina blue', 'Finish colour: Marina blue', 'Available in Jumeirah collection',
  'Colour: Liwa sand', 'available in Al Ain white', 'National Paints Jumeirah range', 'Arabian Ranches style pergola', 'Marina-grade stainless 316 handrail',
  'Marine grade plywood 18 mm', 'Hatta stone cladding', 'Palm fronds for shading', 'Al Jazeera Paints', 'Al Fujairah cement', 'RAK Porcelain sanitaryware',
  'Ras Al Khaimah granite slabs', 'Made in Ras Al Khaimah', 'Made in Sharjah', 'Made in UAE', 'Country of origin: Germany', 'Origin: Italy', 'Origin: China',
  'Country of origin: United Arab Emirates', 'Made in Abu Dhabi by the manufacturer', 'Dubai Investments glass', 'Emirates Glass double glazing', 'Gulf Glass 6 mm clear',
  'Emirates Float Glass', 'Al Ghurair Iron and Steel', 'Conares rebar', 'Emirates Insolaire panels', 'Abu Dhabi Polymers (Borouge)', 'Dubai Aluminium (DUBAL) billets',
  'Masdar certified solar modules', 'Julphar Pharma cleaning kit', 'Akoya pearl white paint', 'Villanova tiles', 'Al Barari landscaping style', 'Sahara beige marble',
  'Oman white marble', 'Galala marble', 'Rolla brush 9 inch', 'Hoshi adhesive', 'Liwan arch design', 'Shamal wind load considered', 'Arjan model chair', 'Remo karama wall plate',
  // standards and authorities
  'Dubai Municipality approved', 'DM-approved materials only', 'DEWA approved meter', 'ADDC approved cable', 'SEWA connection by others', 'FEWA approval', 'Trakhees approval required',
  'Civil Defence approved fire doors', 'Dubai Civil Defence (DCD) approval', 'ESMA certified', 'Abu Dhabi Civil Defence (ADCD) approved', 'Nakheel approval by others', 'Emaar approval',
  'DDA NOC by others', 'JAFZA permit by client', 'Tecom NOC by client', 'MOE approved school furniture', 'MOE school project furniture', 'Dubai Building Code compliant', 'Estidama 2 Pearl',
  'Al Sa\'fat compliant', 'ADQCC certified', 'Dubai Central Laboratory test report', 'DCL test report', 'Third party testing by Dubai Central Laboratory', 'RTA approved road signs',
  'Etisalat approved ducts', 'du approved telecom ducts', 'ISO 9001:2015 certified', 'BS EN 1992-1-1', 'ASTM A123/A123M-17', 'EN 1090-2 EXC2', 'UL listed', 'FM approved',
  'EI 60 fire rated door', 'EI 90 fire rated door, payment 30% advance', 'EI 120 shutter, transfer of title on payment', 'Fire rating EI 60, check on site',
  // delivery terms
  'CIF Jebel Ali', 'FOB Jebel Ali port', 'Ex-works Sharjah', 'Ex works Jebel Ali Free Zone #arguable', 'DDP site', 'Delivery to site in Dubai', 'Delivery within Dubai free of charge',
  'Installation across Abu Dhabi and Al Ain #arguable', 'Delivery to Abu Dhabi, Al Ain and the Western Region #arguable', 'Service centre in Dubai', 'We serve all emirates',
  'Delivery charges extra outside Dubai', 'Ex-stock Dubai', 'Ex-stock Jebel Ali warehouse #arguable', 'Shipped from Khalifa Port #arguable', 'Lead time 4 weeks ex Jebel Ali',
  'Transport to site by others', 'Free delivery in Sharjah and Ajman', 'Delivery to Fujairah extra AED 500',
  // quantities, units, premises-shaped
  'Supply and install 2 TR split unit', 'Unit rate AED 450', 'Rate per unit 12.50', 'unit price as per BOQ', '2 villas', 'villa type B', 'Villa type B 4 nos', 'Villa Type 2 layout',
  'plot area 500 m2', 'Plot area 1,200 sqm', 'office partition 101 mm', 'Office 101 partition', 'OFFICE 101 door D-01', 'Tower crane 6 months', 'Liebherr Tower Crane hire',
  'Potain tower crane 8 t', 'Building works', 'Street lighting pole 9 m', 'floor 3 of 5', 'Block work 200 mm', 'Block 200 mm hollow', 'Road marking paint', 'Reflective Road Studs 100 nos',
  'Cat Eye Road Studs', 'Concrete Road Barrier 2 m', 'Solar Road Studs', 'Asphalt Road works 500 m2', 'Interlock paving 80 mm', 'Shop drawings within 2 weeks', 'Shop 3 nos signage',
  'Flat bar 50x5 mm', 'flat M10 washer', 'Flat 3 mm sheet', 'Apartment block 3 storeys', 'Apartment 2 bedroom layout', 'Showroom display unit 2 nos', 'Warehouse racking 3 bays',
  'Suite 3 rooms', 'House 3 bedrooms', 'House keeping 2 persons', 'Unit 4 of 6 AHU', 'Tower 2 lifts 3 nos', 'Building 3 storeys', 'Block B ground floor', 'Plot boundary wall 200 m',
  'Parcel locker 24 doors', 'Penthouse terrace waterproofing', 'Townhouse type A 3 nos', 'Villa 15 m frontage', 'Villa 5 bedrooms', 'Villa 2 storeys', 'Flat 12 mm glass',
  'Street 2 lanes asphalt', 'Road 7 m wide', 'Lane 3 m', '14th floor slab', 'Level 14 slab', '3rd Street sign',
  // dimensions / codes that look like coordinates / Makani / plot
  'Size 25.4 x 55.2 mm', 'Tolerance 25.400/55.200 mm', 'Pipe 22.225, 55.000 OD', 'Part no. 12345 67890', 'Model 12345-67890', 'Serial 3061295475', 'Rate 25.125, 55.750 per lm',
  'Coordinates to be surveyed by contractor', 'GPS tracker model GT-06', 'Ref ST-37 steel', 'ST-52 steel grade', 'PP-R pipes PN20', 'PP-R 32 mm', 'UPS warranty 2 years', 'UPS 10 kVA',
  'GI-pipe 2 inch', 'GI/0.5 mm duct', 'DC-12V driver', 'AC-2024-12 unit model', 'Drawing A-2026-101 rev B', 'DWG-2025-0034', 'ID-2026-118 door schedule', 'SS-2205 duplex',
  'Approval ref DM-2024-0123', 'Ref CT-1 cooling tower', 'Item MS-01 mirror', 'Mark FT-01 floor trap', 'Type FT-2 floor trap', 'FT-01 floor trap 4 nos',
  // people/contact-shaped
  'Contact adhesive 5 L', 'Contact Adhesive for laminate', 'Manual Call Point 6 nos', 'Call Point, break glass', 'Nurse Call Station', 'Door Contact Switch', 'Auxiliary Contact Block',
  'Magnetic Contact Sensor', 'Phone Socket 2 gang', 'Reach Truck 2.5 t', 'Reach Stacker hire', 'Regards quality, we follow ISO', 'Eng. drawings attached', 'Eng. Drawings attached',
  'Dr. Fixit Pidifin 2K waterproofing', 'Dr. Fixit LW+', 'Call Bell push', 'Call Button for lift', 'Contact Block NO+NC', 'Speak To Supervisor sign', 'WhatsApp Business supported',
  'Coordinate With MEP drawings', 'Contact Clamp 25 mm', 'Call Out Charges AED 150', 'Call Out Fee waived',
  // banks / signatures
  'bank of pumps 3 nos', 'ADCB approved valuer report', 'Bank guarantee 10%', 'Performance bond 10% from a UAE bank', 'Advance payment guarantee', 'Signed and stamped LPO required',
  'Please send the quotation signed and stamped', 'Quotation must be signed and stamped', 'Company stamp required on drawings', 'Authorised signature on the delivery note',
  'Sales Manager approval not required.', 'General Manager office fit-out.', 'Branch Manager cabin partition', 'FAB shop drawings, payment on delivery', 'CBD board 12 mm, payment 50%',
  'HBL cable tray', 'NBF fire rated board', 'DIB connector, transfer on order', 'Mashreq tower fit-out #arguable',
  // landmark-shaped scope
  'Install next to Main Distribution Board', 'Fix beside Pump Room door', 'Mount behind False Ceiling', 'Place in front of Main Entrance', 'Located close to Water Tank',
  'Install near Fire Exit Door', 'Fix opposite Lift Lobby', 'Install next to the DB', 'Mount near the AHU', 'Fix behind the WC', 'close to Kitchen Sink', 'next to Fire Hose Reel',
  'adjacent to Electrical Room', 'near the Main Gate', 'Behind Reception Desk panel', 'In front of Swimming Pool deck',
  // buildings / roads named as products
  'Pre-Engineered Building steel structure', 'Siemens Building Technologies controller', 'Honeywell Building Solutions BMS', 'Siemens Building Automation', 'Steel Building 30 x 60 m',
  'Modular Building cabins', 'Portable Building 6 x 3 m', 'Green Building compliant', 'Lighting Tower 4 x 1000 W', 'Telescopic Tower light', 'Aluminium Tower scaffold',
  'Water Tower 20,000 gal', 'FRP Cooling Tower 200 TR', 'Marley Cooling Tower', 'BAC Tower 300 TR', 'Evapco Tower fill media', 'Clock Tower fit-out #arguable',
  'Wall Street finish panels', 'Service Road paving', 'Access Road 6 m', 'Ring Road lighting', 'Slip Road signage', 'Gravel Road 300 m',
  // misc trade prose
  'All works as per drawings and specifications', 'Two coats of primer and one coat of enamel', 'Supply of 5 nos gate valves DN 50', 'Warranty 10 years on membrane',
  '5 years warranty on workmanship', 'Warranty 2 years against manufacturing defects', 'Services: installation, testing and commissioning', 'Free maintenance for 1 year',
  'AMC available on request', 'Validity 30 days', 'Payment 50% advance, 50% on completion', 'Price excludes VAT 5%', 'Lead time 3-4 weeks', 'Site visit required before installation',
  'Scaffolding by others', 'Power and water by client', 'Night work at extra cost', 'Working hours 8 am to 5 pm', 'Debris removal included', 'Testing and commissioning included',
  'Best quality materials', 'best quality, fast delivery', 'Steel works as per drawing', 'Fast fix anchors M10', 'Smart home automation', 'Royal blue tiles', 'Gulf standard',
  'light fittings LED panel 600x600', 'Al Noor LED panel light', 'noor light 18 W', 'Falcon grey RAL 7012', 'Falcon grey finish', 'ABC fire extinguisher 6 kg', 'ABC dry powder',
  'Standard finish', 'Concealed piping', 'Concealed Cistern', 'Electrical works', 'Electrical Panel', 'Ceramic tiles', 'Granite countertop', 'Thermal insulation 50 mm',
  'Thermostat digital', 'Precision AC unit', 'Insulation 25 mm', 'Christmas lights', 'Marshalling Box', 'Brightness 3000 lm', 'Standard Delivery', 'Constant pressure pump',
  'Construction water', 'Technical submittal', 'Hydrostatic test', 'Stainless steel 316', 'Stainless Steel sink', 'Stainless Steel 304 handrail',
  'Mohammed Bin Rashid Road works #arguable', 'The quality of the joinery is excellent', 'Jebel Ali Free Zone company #arguable',
  'International standards apply', 'International city standards', 'Global village style kiosk', 'City walk paving pattern', 'Town square lighting design', 'Media city style office',
];

export const AR: string[] = [
  'دهان بلون أزرق مارينا طبقتين', 'خلاط مياه سلسلة جميرا', 'أسمنت الشارقة ٥٠ كجم', 'مياه العين ٥٠٠ مل', 'بلاط رأس الخيمة للسيراميك ٦٠×٦٠', 'كابلات دبي (دوكاب)',
  'حديد الإمارات للتسليح', 'معتمد من بلدية دبي', 'معتمد من الدفاع المدني', 'معتمد من هيئة كهرباء ومياه دبي', 'التسليم إلى الموقع في دبي', 'التركيب في أبوظبي والعين',
  'بلد المنشأ: ألمانيا', 'صنع في الإمارات', 'ضمان ٥ سنوات على المصنعية', 'فيلا ٣ غرف نوم', 'فيلا ٥ غرف', 'عدد ٢ فيلا', 'فيلا من طابقين', 'قطعة ٥٠ سم', 'قطعة ١٢ مم',
  'قطعة 2 × 3 متر', 'شقة غرفتين', 'شقة ٣ غرف', 'مكتب ١٠١ قاطع', 'برج التبريد ٢٠٠ طن', 'برج الإنارة', 'مبنى المولدات', 'شارع الخدمة', 'شارع 7 متر عرض',
  'بيت الدرج ٣ طوابق', 'منزل ٣ غرف', 'الدفع ٥٠٪ مقدم', 'الأسعار لا تشمل ضريبة القيمة المضافة', 'التعاون مع المقاول الرئيسي', 'المرور إلى الموقع عبر البوابة',
  'المشرف على الموقع', 'الروضة الخلفية للفيلا', 'العين الساهرة للكاميرا', 'الخيل والفروسية', 'ميدان العمل', 'مربح للطرفين', 'الصفا والنقاء في التشطيب', 'الوصل بين الأنابيب',
  'المنارة المضيئة', 'النخيل الصناعي للحديقة', 'البستان المنزلي', 'الحمراء اللون', 'الرملة البيضاء', 'مسافي للمياه', 'ليوا الرملي', 'الخان القديم ديكور',
  'التشطيب بالقرب من مدخل المبنى', 'تركيب بجانب لوحة التوزيع الرئيسية', 'خلف السقف المستعار', 'أمام المدخل الرئيسي', 'قرب مضخة الحريق', 'بجانب غرفة الكهرباء',
  'رقم القطعة ١٢٣٤٥ ٦٧٨٩٠ للمنتج', 'مقاس ٢٥٫٤ × ٥٥٫٢ مم', 'فيلا ١٥ متر واجهة', 'الختم والتوقيع مطلوب على أمر الشراء', 'يرجى إرسال العرض موقعا ومختوما',
  'بنك المضخات ٣ عدد', 'شارع رئيسي', 'شارع الخدمات', 'برج المياه', 'مبنى الإدارة', 'شقق سكنية ٣ طوابق', 'ديرة', // last is a bare place, expect reduce
];

// The second review's 153 NEW sentences (13 Nov 2026: MEP, joinery, landscape, ELV, signage, marine, catering; 30 Arabic),
// written after the fix without being shown to it.
export const EN2: string[] = [
  // MEP
  'Chilled water pipe 4 inch with 50 mm Armaflex', 'FCU 1.5 TR ceiling concealed type', 'VRF outdoor unit 20 HP', 'Exhaust fan 300 CFM kitchen', 'Fresh air handling unit FAHU-01',
  'Grease duct 1.2 mm black steel', 'Sprinkler pendent K5.6 68 deg C', 'Fire pump 750 GPM diesel', 'Jockey pump 25 GPM', 'Zone control valve 4 inch', 'Hose reel cabinet 30 m',
  'Smoke detector addressable', 'Heat detector rate of rise', 'Sounder beacon red', 'Fire alarm control panel 4 loop', 'Emergency light 3 hour maintained', 'Exit sign LED double sided',
  'MDB 1600 A 4 pole', 'SMDB-G1 250 A', 'DB-L3 lighting board', 'Cable tray 300 x 50 HDG', 'Busbar trunking 2500 A', 'Earth pit with test chamber', 'Lightning arrestor ESE type',
  'Capacitor bank 300 kVAR', 'ATS 800 A', 'Generator 500 kVA prime rated', 'Water heater 80 L', 'Booster pump set duty standby', 'PPR pipe 25 mm hot water', 'Floor drain 100 mm',
  'Manhole cover D400 ductile iron', 'Grease trap 1000 L', 'Septic tank GRP 10 m3', 'Water tank GRP sectional 20 m3', 'Solar water heater 300 L',
  // joinery / fit-out
  'Solid oak door 45 mm with ironmongery', 'Kitchen cabinets MDF lacquered high gloss', 'Wardrobe sliding doors 2.4 m', 'Vanity unit with quartz top', 'Skirting MDF 100 mm painted',
  'Wall cladding HPL 12 mm', 'Reception counter Corian finish', 'Acoustic panel fabric wrapped 25 mm', 'Gypsum ceiling 12.5 mm moisture resistant', 'Bulkhead with LED cove light',
  'Raised access floor 600 x 600', 'Glass partition 12 mm frameless', 'Door closer EN 3-6', 'Lever handle satin stainless', 'Hinges 4 inch ball bearing', 'Mortise lock euro cylinder',
  // landscaping
  'Washingtonia palm 4 m clear trunk', 'Date palm relocation', 'Ghaf tree 3 m', 'Bougainvillea 1.5 m', 'Paspalum turf', 'Irrigation drip line 16 mm', 'Pop-up sprinkler 4 inch',
  'Irrigation controller 12 station', 'Interlock pavers 60 mm grey', 'Kerb stone 500 x 250', 'Pergola WPC 3 x 4 m', 'Water feature pump 1 hp', 'Artificial grass 35 mm',
  'Topsoil red sand 300 mm', 'Planter box GRC', 'Garden lighting bollard 1 m',
  // IT / ELV
  'Cat6 cable LSZH 305 m', 'Patch panel 24 port', 'Network rack 42U', 'Fibre optic 12 core single mode', 'IP camera 4 MP dome', 'NVR 32 channel', 'Access control reader card and PIN',
  'Video intercom villa kit', 'PA system speaker ceiling 6 W', 'MATV outlet', 'Wi-Fi access point ceiling mounted', 'Structured cabling certification Fluke', 'Door Access Controller 2 door',
  'Turnstile tripod', 'Barrier gate 4 m boom', 'Server room FM200 system', 'Rack PDU 16 A', 'SOC 24/7 monitoring optional',
  // signage
  'Signage acrylic 3D letters 300 mm', 'Pylon sign 6 m illuminated', 'Wayfinding sign aluminium composite', 'Vinyl frosted film', 'Neon flex LED sign', 'Directory board lobby',
  'Shopfront signage channel letters', 'Car park signage reflective',
  // marine
  'Marine plywood 18 mm BS 1088', 'Pontoon floating 2 x 10 m', 'Boat lift 5 t', 'Mooring bollard cast iron', 'Fender rubber D type', 'Anti-fouling paint 2 coats', 'Gangway aluminium 8 m',
  'Marine grade 316 cleats', 'Dock box with light',
  // catering equipment
  'Combi oven 10 tray', 'Gas range 6 burner with oven', 'Walk-in chiller 3 x 3 m', 'Undercounter fridge 2 door', 'Dishwasher hood type', 'Hood with Ansul system', 'Ice machine 150 kg',
  'Bain marie 4 pan', 'Stainless steel work table 1800 mm', 'Sink 2 bowl with drainer', 'Pass-through window', 'Fryer 2 x 10 L electric',
  // terms and prose
  'Commissioning by manufacturer representative', 'Spare parts for 2 years included', 'Training for client staff 1 day', 'As-built drawings in 3 sets', 'O&M manuals 2 copies',
  'Defects liability period 12 months', 'Retention 10% released after DLP', 'Mobilisation 1 week from LPO',
];
export const AR2: string[] = [
  'وحدة تكييف مخفية ١٫٥ طن', 'مضخة حريق ديزل ٧٥٠ جالون', 'كاشف دخان عنواني', 'لوحة توزيع رئيسية ١٦٠٠ أمبير', 'حامل كابلات ٣٠٠ × ٥٠ مجلفن', 'سخان مياه ٨٠ لتر',
  'باب خشب بلوط ٤٥ مم', 'خزائن مطبخ لامعة', 'سقف جبس مقاوم للرطوبة', 'فاصل زجاجي ١٢ مم', 'نخلة واشنطونيا ٤ متر', 'شبكة ري بالتنقيط ١٦ مم', 'بلاط إنترلوك رمادي ٦٠ مم',
  'كاميرا مراقبة ٤ ميجا', 'كابل شبكة كات ٦', 'نظام اتصال داخلي للفيلا', 'لافتة حروف بارزة ٣٠٠ مم', 'لوحة إرشادية ألمنيوم', 'خشب بحري ١٨ مم', 'رصيف عائم ٢ × ١٠ متر',
  'فرن كومبي ١٠ صواني', 'ثلاجة غرفة ٣ × ٣ متر', 'طاولة عمل ستانلس ستيل ١٨٠٠ مم', 'مغسلة حوضين', 'التشغيل والاختبار بواسطة الوكيل', 'قطع غيار لمدة سنتين',
  'فترة الصيانة ١٢ شهر', 'تدريب موظفي العميل يوم واحد', 'المخططات النهائية ٣ نسخ', 'المحجوز ١٠٪ يصرف بعد فترة الضمان',
];

// The third review's 80 sentences aimed at the new place rules (13 Nov 2026).
export const EN3: string[] = [
  'Springs 5 mm thick', 'Gas springs 2 nos', 'Door closer springs 3 sets', 'Lakes 2 nos', 'Greens 3 kg', 'Greens 4 trays microgreens', 'Meadows 2 bags seed mix', 'Meadow grass 5 kg',
  'villa type fifteen layout', 'villas no. 40 to 45 on the drawing', 'Villas 4 nos type A', 'cluster 22 lights', 'Cluster 3 pendant lights', 'LED cluster 12 W', 'Sector 3 of the drawing',
  'Sector 2 valve', 'M-37 bolt', 'M-12 anchor bolt', 'ME-10 fitting', 'SE-45 valve', 'SE-45 sealant', 'Mussafah supplier type ME-10 valve', 'ICAD grade steel', 'MBZ-1 panel',
  'Shabiya pattern tiles', '23B Street light pole', 'Street light pole 23B', 'Type 23B street light', 'Al Wasl paint colour', 'Al Wasl area rug', 'Area 12 m2', 'area 12 m2 tiles',
  'Industrial 1 mm sheet', 'Industrial 2 coat epoxy', 'Ajman Industrial supplier', 'Industrial Area lighting fixture', 'Dubai Hospital-grade vinyl', 'Hospital grade paint', 'Hospital 2 beds',
  'Al Ghurair Centre style', 'Centre 2 table', 'Center line 1 m', 'Unit 4, 2 TR', 'Unit 4 of 6', 'Shop 3 drawings', 'Shop 3, rev B', 'Office 14 chairs', 'Office 14, 2 desks',
  'Warehouse 7 racks', 'Warehouse 7, 3 bays', 'Cluster 22, LED', 'Office 302 partition', 'Office 302, glass partition 12 mm', 'Shop 3, Karama paint finish', 'Unit 4, Al Wasl paint',
  'Showroom 2, display units', 'Suite 5, 3 rooms', 'at site in Dubai', 'at Dubai site', 'at 5 m height', 'at grid line C', 'at level 3', 'at Al Ain white finish', 'Lakes blue paint',
  'Greens and blues palette', 'Springs Lakes Greens collection', 'District cooling connection', 'District 9 font', 'Block 200 mm, Sector 3',
  'Hatta pattern', 'Masdar-certified panel', 'Karama 2 seater sofa', 'Deira 3 piece set',
];
export const AR3: string[] = [
  'نوابض ٥ مم', 'مكتب ١٤ كرسي', 'محل ٣ مخططات', 'مستودع ٧ رفوف', 'المنطقة الصناعية للأرضيات طبقتين', 'قطاع ٣ من المخطط', 'كتلة ٢٢ إضاءة',
];
