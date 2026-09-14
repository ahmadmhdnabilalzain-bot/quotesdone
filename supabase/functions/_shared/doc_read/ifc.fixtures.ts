// ifc fixtures — a small IFC4 model whose true quantities are known by construction.
// Imported by ifc.test.ts and by the before/after audit; pure, no I/O.
//
// ifcFixture(): length unit MILLI METRE. One storey "Level 1". Two IfcWall of IfcWallType
// 'Basic Wall 200mm'. Qto_WallBaseQuantities: NetSideArea 15.0 + 12.5 = 27.5 sqm; Length 5000 + 4000 mm
// = 9.000 m. One IfcSpace with an Arabic LongName written as \X2\ UTF-16, a '' escape, a comment and a
// multi-line instance.
export const IFC_FIXTURE_TEXT = `ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('ViewDefinition [ReferenceView_V1.2]'),'2;1');
FILE_NAME('zz-demo.ifc','2026-09-14T00:00:00',('ZZ DEMO'),('ZZ DEMO'),'','','');
FILE_SCHEMA(('IFC4'));
ENDSEC;
DATA;
/* project and units */
#1=IFCPROJECT('0YvctVUKr0kugbFTf53O9L',$,'ZZ DEMO Villa',$,$,'ZZ DEMO Villa, Architect''s issue',$,(#20),#10);
#10=IFCUNITASSIGNMENT((#11,#12,#13));
#11=IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.);
#12=IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.);
#13=IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.);
#20=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#21,$);
#21=IFCAXIS2PLACEMENT3D(#22,$,$);
#22=IFCCARTESIANPOINT((0.,0.,0.));
#30=IFCBUILDINGSTOREY('1kTvXnbbzCWw8lcMd1dR4o',$,'Level 1',$,$,$,$,$,.ELEMENT.,0.);
#40=IFCWALL('2O2Fr$t4X7Zf8NOew3FLOH',$,'Basic Wall:Basic Wall 200mm:1',$,'Basic Wall:Basic Wall 200mm',$,$,'1001',.STANDARD.);
#41=IFCWALL('2O2Fr$t4X7Zf8NOew3FLOI',$,'Basic Wall:Basic Wall 200mm:2',$,'Basic Wall:Basic Wall 200mm',$,$,'1002',.STANDARD.);
#45=IFCSPACE('3a4T5b6C7d8E9f0G1h2I3j',$,'101',$,$,$,$,'\\X2\\063A063106410629\\X0\\ 1',.ELEMENT.,.INTERNAL.,$);
#50=IFCWALLTYPE('1xS3BCk291UvhgP2dvNsgp',$,'Basic Wall 200mm',$,$,$,$,$,$,.STANDARD.);
#51=IFCRELDEFINESBYTYPE('0Yz1Xk5Yb4sQ7p8R9t0U1v',$,$,$,(#40,#41),#50);
#60=IFCRELCONTAINEDINSPATIALSTRUCTURE('2Rt5Yu7Io9Pa1Sd3Fg5Hj7',$,$,$,
  (#40,#41,#45),
  #30);
#70=IFCQUANTITYAREA('NetSideArea',$,$,15.,$);
#71=IFCQUANTITYLENGTH('Length',$,$,5000.,$);
#72=IFCELEMENTQUANTITY('3Kl4Mn5Op6Qr7St8Uv9Wx0',$,'Qto_WallBaseQuantities',$,$,(#70,#71));
#73=IFCQUANTITYAREA('NetSideArea',$,$,12.5,$);
#74=IFCQUANTITYLENGTH('Length',$,$,4000.,$);
#75=IFCELEMENTQUANTITY('3Kl4Mn5Op6Qr7St8Uv9Wy1',$,'Qto_WallBaseQuantities',$,$,(#73,#74));
#76=IFCRELDEFINESBYPROPERTIES('0Ab1Cd2Ef3Gh4Ij5Kl6Mn7',$,$,$,(#40),#72);
#77=IFCRELDEFINESBYPROPERTIES('0Ab1Cd2Ef3Gh4Ij5Kl6Mn8',$,$,$,(#41),#75);
ENDSEC;
END-ISO-10303-21;
`;

export const ifcFixture = (): Uint8Array => new TextEncoder().encode(IFC_FIXTURE_TEXT);
