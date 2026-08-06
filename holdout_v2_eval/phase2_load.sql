do $HOLDOUT_V2_LOAD$
declare
  v_parts text; v_doc text; v_sum text; v_n integer;
  c_expected constant text := '44973f9169510a06468a20eb2ba068f932e25bdd9ad7e0d85d4479b5e03d4801';
begin
  ------------------------------------------------------ 1. private schema and tables
  create schema holdout_v2;
  revoke all on schema holdout_v2 from public;
  revoke all on schema holdout_v2 from anon, authenticated;
  grant usage on schema holdout_v2 to postgres, service_role;

  create table holdout_v2.case_v2 (
    case_key            text primary key,
    bucket              text not null,
    adversarial         boolean not null,
    gulf_phrasing       boolean not null,
    mixed_language      boolean not null,
    morphology_variant  text,
    text_en             text not null,
    text_ar             text not null,
    documents           jsonb not null,
    expect              jsonb not null,
    rationale           text not null,
    spec_refs           text[] not null,
    case_json           text not null,
    loaded_at           timestamptz not null default now()
  );

  create table holdout_v2.seal (
    id                  integer primary key default 1,
    holdout_version     text not null,
    checksum_sha256     text not null,
    case_count          integer not null,
    seal_document       jsonb not null,
    bundle_manifest_sha text not null,
    loaded_checksum     text,
    checksum_verified   boolean,
    loaded_at           timestamptz not null default now(),
    loaded_by           text not null,
    constraint seal_single_row check (id = 1)
  );

  create table holdout_v2.result_of_record (
    result_id           bigint generated always as identity primary key,
    holdout_version     text not null,
    commit_sha          text not null,
    branch              text not null,
    schema_state        jsonb not null,
    bundle_checksum     text not null,
    cases_checksum      text not null,
    executed_at         timestamptz not null,
    completed_at        timestamptz not null,
    case_count          integer not null,
    interpretations     integer not null,
    metrics             jsonb not null,
    latency             jsonb not null,
    failure_summary     jsonb not null,
    evaluator_notes     text not null,
    recorded_at         timestamptz not null default now()
  );

  create table holdout_v2.result_interpretation (
    result_id           bigint not null references holdout_v2.result_of_record(result_id),
    case_key            text not null references holdout_v2.case_v2(case_key),
    lang                text not null check (lang in ('en','ar')),
    raw_output          jsonb not null,
    normalised          jsonb not null,
    expected            jsonb not null,
    field_match         jsonb not null,
    exact_match         boolean not null,
    latency_ms          numeric not null,
    primary key (result_id, case_key, lang)
  );

  create table holdout_v2.result_case_verdict (
    result_id           bigint not null references holdout_v2.result_of_record(result_id),
    case_key            text not null references holdout_v2.case_v2(case_key),
    verdict             text not null,
    parity              boolean not null,
    failure_class       text,
    diagnosis           text,
    detail              jsonb not null,
    primary key (result_id, case_key)
  );

  alter table holdout_v2.case_v2               enable row level security;
  alter table holdout_v2.seal                  enable row level security;
  alter table holdout_v2.result_of_record      enable row level security;
  alter table holdout_v2.result_interpretation enable row level security;
  alter table holdout_v2.result_case_verdict   enable row level security;

  ------------------------------------------------------ 2. insert all 131 cases
  insert into holdout_v2.case_v2
    (case_key,bucket,adversarial,gulf_phrasing,mixed_language,morphology_variant,
     text_en,text_ar,documents,expect,rationale,spec_refs,case_json)
  select j->>'case_key', j->>'bucket',
         (j->>'adversarial')::boolean, (j->>'gulf_phrasing')::boolean,
         (j->>'mixed_language')::boolean,
         j->>'morphology_variant',
         j->>'text_en', j->>'text_ar',
         j->'documents', j->'expect', j->>'rationale',
         array(select jsonb_array_elements_text(j->'spec_refs')),
         v.t
  from (values
    ('{
  "adversarial": false,
  "bucket": "included_plain",
  "case_key": "A-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "plumbing"
    ],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "definite_article",
  "rationale": "A direct request to price a single named trade with no lifecycle split detects hvac as included and active. No other trade is named, so nothing else is detected.",
  "spec_refs": [
    "2.1",
    "2.2",
    "2.4"
  ],
  "text_ar": "نقوم بإعداد مناقصة لفيلا جديدة في البرشاء ونود الحصول على عرض سعركم لأعمال التكييف والتهوية.",
  "text_en": "We are preparing a tender for a new villa in Al Barsha and would like your quotation for the HVAC works."
}'),
    ('{
  "adversarial": false,
  "bucket": "included_plain",
  "case_key": "A-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A plain in-scope request for one named trade yields included at trade level. With no split stated the trade emits a single complete_trade_scope row.",
  "spec_refs": [
    "2.2",
    "2.4"
  ],
  "text_ar": "نرجو تزويدنا بأفضل سعر لأعمال الكهرباء لمستودع في مجمع دبي للاستثمار.",
  "text_en": "Please provide your best price for the electrical works for a warehouse in Dubai Investments Park."
}'),
    ('{
  "adversarial": false,
  "bucket": "included_plain",
  "case_key": "A-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "dual",
  "rationale": "Plumbing and sanitaryware are one trade in the approved vocabulary, so a single trade is detected as included. The Arabic dual form carries the same specificity as the English.",
  "spec_refs": [
    "2.1",
    "2.2"
  ],
  "text_ar": "نرجو إرسال عرضكم لأعمال السباكة والأدوات الصحية لفيلا مكونة من طابقين.",
  "text_en": "Kindly send us your offer for the plumbing and sanitaryware works for a two-storey villa."
}'),
    ('{
  "adversarial": false,
  "bucket": "included_plain",
  "case_key": "A-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire",
      "plumbing"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Two trades are named directly and both are in scope, so both are detected as included and both activate. Naming two trades does not reach any third trade.",
  "spec_refs": [
    "2.2",
    "2.8"
  ],
  "text_ar": "لأعمال تجهيز المكاتب في الخليج التجاري نحتاج تسعير أعمال التكييف وأعمال الكهرباء معًا.",
  "text_en": "For the office fit-out at Business Bay we need the HVAC works and the electrical works quoted together."
}'),
    ('{
  "adversarial": false,
  "bucket": "included_plain",
  "case_key": "A-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "included",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Fire is named directly, so it is detected without any umbrella involvement. The text addresses the approvals stage explicitly, which states a split and therefore replaces the complete_trade_scope row.",
  "spec_refs": [
    "2.1",
    "2.4"
  ],
  "text_ar": "نرجو تسعير أعمال الحريق والسلامة للمحل التجاري، بما في ذلك تقديم المعاملة والحصول على موافقة الدفاع المدني.",
  "text_en": "Please quote the fire and life safety works for the retail unit, including the Civil Defence submission and approval."
}'),
    ('{
  "adversarial": false,
  "bucket": "included_plain",
  "case_key": "A-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "elv"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "elv": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "plural",
  "rationale": "ELV is named directly and its subject matter is listed, so elv is detected as included. Naming ELV equipment does not reach the electrical trade.",
  "spec_refs": [
    "2.1",
    "2.2"
  ],
  "text_ar": "نطلب عرض سعر لأنظمة التيار الخفيف والأمن، من كاميرات المراقبة وأنظمة التحكم بالدخول وشبكات الكابلات المهيكلة، للعيادة الجديدة في العين.",
  "text_en": "We require a quotation for the ELV and security systems, covering CCTV, access control and structured cabling, for the new clinic in Al Ain."
}'),
    ('{
  "adversarial": true,
  "bucket": "included_plain",
  "case_key": "A-007",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An umbrella reference to the combined mechanical, electrical and plumbing services reaches the three core trades only. Fire and ELV are never reached implicitly and must not be detected here.",
  "spec_refs": [
    "2.1",
    "2.2"
  ],
  "text_ar": "أعمال الميكانيكا والكهرباء والصحية للفيلا ضمن نطاق عملنا، نرجو تسعيرها.",
  "text_en": "The MEP works for the villa are within our scope; kindly price them."
}'),
    ('{
  "adversarial": false,
  "bucket": "included_plain",
  "case_key": "A-008",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire",
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "fire"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "fire",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "hvac"
    ],
    "trade_dispositions": {
      "fire": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": true,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Fire is named directly alongside plumbing, so both are detected as included and both activate. Direct naming is the only route by which fire enters a case.",
  "spec_refs": [
    "2.1",
    "2.2"
  ],
  "text_ar": "نرجو تسعير أعمال السباكة وأعمال مكافحة الحريق لسكن العمال في جبل علي.",
  "text_en": "Kindly quote the plumbing works and the fire fighting works for the labour accommodation in Jebel Ali."
}'),
    ('{
  "adversarial": false,
  "bucket": "excluded_no_party",
  "case_key": "B-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "excluded",
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The removal of electrical tells us what we are not doing but identifies nobody else, so the disposition is excluded rather than by_others. Electrical is still detected because the text gives evidence of it.",
  "spec_refs": [
    "2.3",
    "2.8"
  ],
  "text_ar": "عرضنا يشمل أعمال التكييف فقط؛ أعمال الكهرباء غير مشمولة في نطاق عملنا.",
  "text_en": "Our quotation covers the HVAC works only; the electrical works are not included in our scope."
}'),
    ('{
  "adversarial": false,
  "bucket": "excluded_no_party",
  "case_key": "B-002",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "plumbing": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "alef_variant",
  "rationale": "A single trade is removed from scope with no other party identified, so it is detected as excluded and does not contribute. With no trade active the no_active_trade blocker is raised.",
  "spec_refs": [
    "2.3",
    "2.9"
  ],
  "text_ar": "اعمال السباكة مستثناة من هذا العرض.",
  "text_en": "The plumbing works are excluded from this proposal."
}'),
    ('{
  "adversarial": false,
  "bucket": "excluded_no_party",
  "case_key": "B-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "fire"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "fire",
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "excluded",
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Fire is named and removed with no responsible party identified, so it is excluded and detected. HVAC remains the only active trade.",
  "spec_refs": [
    "2.3",
    "2.8"
  ],
  "text_ar": "سنقوم بتنفيذ أعمال التكييف. أما أعمال مكافحة الحريق فهي خارج نطاق هذا العرض.",
  "text_en": "We will carry out the HVAC works. The fire fighting works are outside the scope of this offer."
}'),
    ('{
  "adversarial": false,
  "bucket": "excluded_no_party",
  "case_key": "B-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "electrical",
      "elv"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included",
      "elv": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "ELV is named and removed without any other party being identified, which is excluded and not by_others. Electrical contributes and activates.",
  "spec_refs": [
    "2.2",
    "2.3"
  ],
  "text_ar": "أعمال الكهرباء مشمولة. أما أنظمة التيار الخفيف والأمن فليست جزءًا مما سنقوم بتنفيذه.",
  "text_en": "Electrical works are included. The ELV and security systems are not part of what we will deliver."
}'),
    ('{
  "adversarial": false,
  "bucket": "excluded_no_party",
  "case_key": "B-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "excluded",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "proclitic",
  "rationale": "Dropping a trade from our scope without naming a successor is excluded. Plumbing is unaffected and remains active.",
  "spec_refs": [
    "2.3"
  ],
  "text_ar": "نقوم بتسعير حزمة أعمال السباكة، وقد استُبعدت أعمال الكهرباء من نطاقنا في هذا المشروع.",
  "text_en": "We are pricing the plumbing package. The electrical works have been dropped from our scope on this project."
}'),
    ('{
  "adversarial": true,
  "bucket": "excluded_no_party",
  "case_key": "B-006",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [
      "hvac"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Language that removes a trade from our scope does not by itself say who will do it, so the disposition is excluded and never by_others. The trade is detected but does not activate.",
  "spec_refs": [
    "2.3",
    "2.8"
  ],
  "text_ar": "أعمال التكييف غير مشمولة في نطاق أعمالنا.",
  "text_en": "The HVAC works are not included in our scope of works."
}'),
    ('{
  "adversarial": true,
  "bucket": "excluded_no_party",
  "case_key": "B-007",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "excluded",
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A completeness modifier qualifying a trade term widens the extent of the statement it sits in but does not change its disposition, so the electrical scope is excluded in full. HVAC is separately included.",
  "spec_refs": [
    "2.3",
    "2.6"
  ],
  "text_ar": "حزمة أعمال الكهرباء الكاملة مستثناة من عرضنا؛ نحن نسعّر أعمال التكييف فقط.",
  "text_en": "The complete electrical package is excluded from our offer; we are quoting the HVAC works only."
}'),
    ('{
  "adversarial": false,
  "bucket": "excluded_no_party",
  "case_key": "B-008",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "elv"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "fire"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included",
      "elv": "excluded",
      "fire": "excluded",
      "hvac": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "All five trades are named directly, so all five are detected. The two non-core trades are removed with no other party identified and are therefore excluded.",
  "spec_refs": [
    "2.1",
    "2.3",
    "2.8"
  ],
  "text_ar": "أعمال التكييف والكهرباء والسباكة كلها ضمن نطاقنا. أما أعمال مكافحة الحريق والتيار الخفيف فمستثناة.",
  "text_en": "HVAC, electrical and plumbing are all in our scope. Fire fighting and ELV are excluded."
}'),
    ('{
  "adversarial": false,
  "bucket": "by_others_named",
  "case_key": "C-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "by_others",
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A responsible party is identified by role, so the electrical trade is by_others rather than excluded. HVAC is included and is the only active trade.",
  "spec_refs": [
    "2.2",
    "2.3"
  ],
  "text_ar": "سيقوم مقاول الباطن التابع للمقاول الرئيسي بتنفيذ أعمال الكهرباء؛ ونحن نسعّر أعمال التكييف فقط.",
  "text_en": "The electrical works will be carried out by the main contractor''s own subcontractor; we are pricing the HVAC only."
}'),
    ('{
  "adversarial": false,
  "bucket": "by_others_named",
  "case_key": "C-002",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "by_others"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Another party is identified by role and by appointing organisation, so fire is by_others and is detected without activating. No trade is active, so the no_active_trade blocker is raised.",
  "spec_refs": [
    "2.3",
    "2.9"
  ],
  "text_ar": "أعمال مكافحة الحريق تقع على عاتق المقاول المتخصص المعيّن مباشرة من قبل المطوّر.",
  "text_en": "Fire fighting is under the specialist contractor appointed directly by the developer."
}'),
    ('{
  "adversarial": false,
  "bucket": "by_others_named",
  "case_key": "C-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "electrical",
      "elv"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included",
      "elv": "by_others"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An identified third party holds the ELV package, which is by_others and not client_supplied because the integrator is not the counterparty itself. Electrical is included.",
  "spec_refs": [
    "2.3"
  ],
  "text_ar": "حزمة التيار الخفيف مع مزوّد أنظمة تقنية المعلومات لدى العميل. وسنتولى نحن أعمال الكهرباء.",
  "text_en": "The ELV package is with the client''s IT integrator. We will handle the electrical works."
}'),
    ('{
  "adversarial": true,
  "bucket": "by_others_named",
  "case_key": "C-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [
      "plumbing"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "included",
      "plumbing": "by_others"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The bare construction designating a third party is understood by the reader as identifying another responsible party, so plumbing is by_others rather than excluded. The other two named trades are included.",
  "spec_refs": [
    "2.3"
  ],
  "text_ar": "أعمال السباكة على عهدة الغير. نرجو تسعير نطاق التكييف والكهرباء.",
  "text_en": "Plumbing is by others. Please quote the HVAC and electrical scope."
}'),
    ('{
  "adversarial": false,
  "bucket": "by_others_named",
  "case_key": "C-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "by_others",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A component-level statement about a named trade defeats the trade-level statement for that component only, so approvals are by_others while the unstated components inherit included. The trade stays active because its trade-level disposition contributes.",
  "spec_refs": [
    "2.4",
    "2.5"
  ],
  "text_ar": "سيتولى الاستشاري تقديم موافقات الجهات الخاصة بأعمال الكهرباء، أما بقية نطاق أعمال الكهرباء فهي علينا.",
  "text_en": "The authority approvals for the electrical works will be submitted by the consultant; the rest of the electrical scope is ours."
}'),
    ('{
  "adversarial": false,
  "bucket": "by_others_named",
  "case_key": "C-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "by_others",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A nominated subcontractor is an identified other party, so HVAC is by_others and detected but not active. Plumbing is included.",
  "spec_refs": [
    "2.3",
    "2.8"
  ],
  "text_ar": "أعمال التكييف مع مقاول الباطن المسمّى في وثائق المناقصة؛ نرجو تسعير أعمال السباكة فقط.",
  "text_en": "HVAC is with the nominated subcontractor named in the tender; kindly quote the plumbing works only."
}'),
    ('{
  "adversarial": false,
  "bucket": "by_others_named",
  "case_key": "C-007",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "elv"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "elv",
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "by_others",
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The developer is identified as the responsible party for the security scope, making it by_others. Fire is named directly and remains included.",
  "spec_refs": [
    "2.1",
    "2.3"
  ],
  "text_ar": "أنظمة الأمن ضمن حزمة المطوّر المباشرة، وتبقى أعمال الحريق والسلامة لدينا.",
  "text_en": "The security systems are in the developer''s direct package. The fire and life safety works remain with us."
}'),
    ('{
  "adversarial": false,
  "bucket": "client_supplied",
  "case_key": "D-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "commissioning",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "supply",
        "disposition": "client_supplied",
        "trade": "hvac"
      },
      {
        "component": "testing",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The counterparty providing equipment is client_supplied and must not collapse into by_others, and it sits on the supply component only. The trade is active because its trade-level disposition contributes and the remaining stages are ours.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "سيقوم العميل بتوريد المبردات، وعلينا تركيبها واختبارها وتشغيلها وتسليمها.",
  "text_en": "The chillers will be supplied by the client; we are to install, test and commission them."
}'),
    ('{
  "adversarial": false,
  "bucket": "client_supplied",
  "case_key": "D-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "plumbing"
      },
      {
        "component": "supply",
        "disposition": "client_supplied",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Free issue by the counterparty is client_supplied on the supply component while the fixing work stays ours. The trade remains active with one non-contributing component.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "جميع الأدوات الصحية يوردها العميل مجانًا وسنقوم نحن بتركيبها.",
  "text_en": "All sanitary wares are free issue by the client and will be fixed by us."
}'),
    ('{
  "adversarial": false,
  "bucket": "client_supplied",
  "case_key": "D-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "supply",
        "disposition": "client_supplied",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "spelling",
  "rationale": "Materials provided by the counterparty are client_supplied on the supply stage, and the installation stage remains included. Tender-document misspellings do not change the reading.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "وحدات الانارة يوردها العميل، وسعرنا يشمل التركيبات الكهربائيه فقط.",
  "text_en": "Light fittings are client supplied; our price is for the electrical installation only."
}'),
    ('{
  "adversarial": false,
  "bucket": "client_supplied",
  "case_key": "D-004",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "client_supplied",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [
      "elv"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "client_supplied"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The counterparty provides the equipment and no work around it is requested, so the trade-level disposition is client_supplied and does not contribute. With no active trade the no_active_trade blocker is raised.",
  "spec_refs": [
    "2.2",
    "2.3",
    "2.9"
  ],
  "text_ar": "كاميرات المراقبة وأجهزة التسجيل يوفرها العميل من مشترياته المركزية، ولا يوجد نطاق آخر مطلوب من أعمال التيار الخفيف.",
  "text_en": "The CCTV cameras and recorders are provided by the client from their central procurement, and no other ELV scope is requested."
}'),
    ('{
  "adversarial": true,
  "bucket": "client_supplied",
  "case_key": "D-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "supply",
        "disposition": "client_supplied",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The employer is the counterparty, not a third party, so this is client_supplied and not by_others even though someone other than us provides the material. The distinction changes who is invoiced and must survive.",
  "spec_refs": [
    "2.3"
  ],
  "text_ar": "مواد مجاري الهواء يوردها صاحب العمل مجانًا، ويبقى التركيب ضمن نطاقنا.",
  "text_en": "The ductwork material is free issue by the employer; the installation remains in our scope."
}'),
    ('{
  "adversarial": false,
  "bucket": "client_supplied",
  "case_key": "D-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "fire"
      },
      {
        "component": "supply",
        "disposition": "client_supplied",
        "trade": "fire"
      },
      {
        "component": "testing",
        "disposition": "included",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Fire is named directly and the counterparty supplies the equipment, so supply is client_supplied while installation and testing are included. The trade contributes and activates.",
  "spec_refs": [
    "2.1",
    "2.3",
    "2.4"
  ],
  "text_ar": "سيسلمنا العميل طفايات الحريق وبكرات الخراطيم، وسنقوم بتركيبها واختبارها.",
  "text_en": "The client will hand over the fire extinguishers and hose reels to us; we will install and test them."
}'),
    ('{
  "adversarial": true,
  "bucket": "client_supplied",
  "case_key": "D-007",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "plumbing"
      },
      {
        "component": "supply",
        "disposition": "client_supplied",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac"
    ],
    "trade_dispositions": {
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Counterparty supply is client_supplied on the supply stage, and the reference to a main contractor attaches to builder''s work rather than to any trade in the vocabulary. No second trade is detected from a non-trade subject.",
  "spec_refs": [
    "2.3",
    "2.6"
  ],
  "text_ar": "يقوم العميل بتوريد مضخات التقوية، وأعمال البناء في غرفة المضخات مع المقاول الرئيسي، ونقوم نحن بتنفيذ أعمال تركيب السباكة.",
  "text_en": "The client supplies the booster pumps, the builder''s work in the pump room is with the main contractor, and we carry out the plumbing installation."
}'),
    ('{
  "adversarial": false,
  "bucket": "optional",
  "case_key": "E-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": "optional_pending_decision",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "maintenance",
        "disposition": "optional",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An option sits on the maintenance component while the trade itself is clean and active, and a clarifying component disposition demands clarification on its own. The unresolved option changes the quoted component scope, so the clarification_pending blocker applies.",
  "spec_refs": [
    "2.4",
    "2.7",
    "2.9"
  ],
  "text_ar": "أعمال التكييف ضمن نطاقنا. ونعرض عقد صيانة لمدة سنة كخيار اختياري لتقديره من جانبكم.",
  "text_en": "The HVAC works are in our scope. A one-year maintenance contract is offered as an option for your consideration."
}'),
    ('{
  "adversarial": false,
  "bucket": "optional",
  "case_key": "E-002",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "optional_pending_decision",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "optional",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [
      "elv"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "optional"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A provisional item on which the customer has not decided is optional, which never activates and always clarifies. No trade is active, so both the clarification and the no_active_trade blockers are raised.",
  "spec_refs": [
    "2.2",
    "2.3",
    "2.9"
  ],
  "text_ar": "حزمة التيار الخفيف والأمن مسعّرة كبند احتياطي، ولم يقرر العميل بعد المضي فيها.",
  "text_en": "The ELV and security package is quoted as a provisional item; the client has not yet decided whether to proceed."
}'),
    ('{
  "adversarial": false,
  "bucket": "optional",
  "case_key": "E-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": "optional_pending_decision",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "design",
        "disposition": "optional",
        "trade": "electrical"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The design stage is offered as an option while the installation stage is included, so the trade is active with a clarifying component. Clarification is required even though the trade-level disposition is clean.",
  "spec_refs": [
    "2.4",
    "2.7"
  ],
  "text_ar": "التركيبات الكهربائية مشمولة. والتصميم التفصيلي معروض كخيار إذا رغبتم بأن نتولاه.",
  "text_en": "The electrical installation is included. Detailed design is offered as an option if you wish us to take it on."
}'),
    ('{
  "adversarial": false,
  "bucket": "optional",
  "case_key": "E-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": "optional_pending_decision",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "optional",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included",
      "plumbing": "optional"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "alef_variant",
  "rationale": "An option at trade level does not activate and requires clarification, so plumbing is detected but excluded from the active set. HVAC remains active, so no_active_trade is not raised.",
  "spec_refs": [
    "2.2",
    "2.7",
    "2.9"
  ],
  "text_ar": "اعمال التكييف مؤكدة. أما أعمال السباكة فمعروضة كخيار وسيقرر العميل لاحقًا.",
  "text_en": "HVAC is confirmed. The plumbing works are offered as an option and the client will decide later."
}'),
    ('{
  "adversarial": false,
  "bucket": "optional",
  "case_key": "E-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "elv"
    ],
    "clarification_reason": "optional_pending_decision",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "coordination",
        "disposition": "optional",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The coordination stage carries the option while the trade stays active, which is exactly the shape a trade-level-only reading drops. The answer changes what a supplier would be told to do, so the clarification blocker applies.",
  "spec_refs": [
    "2.4",
    "2.7",
    "2.9"
  ],
  "text_ar": "أعمال التيار الخفيف مشمولة. والتنسيق مع مقاول التشطيبات الداخلية معروض كبند اختياري.",
  "text_en": "The ELV works are included. Coordination with the interior fit-out contractor is offered as an optional item."
}'),
    ('{
  "adversarial": false,
  "bucket": "future_phase",
  "case_key": "F-001",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "future_phase",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [
      "elv"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "future_phase"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Work assigned to a later phase is future_phase, which never activates. Future phase is not a clarifying disposition, so clarification is not required.",
  "spec_refs": [
    "2.2",
    "2.3"
  ],
  "text_ar": "أنظمة التيار الخفيف والأمن تعود إلى المرحلة الثانية من المشروع.",
  "text_en": "The ELV and security systems belong to Phase 2 of the development."
}'),
    ('{
  "adversarial": false,
  "bucket": "future_phase",
  "case_key": "F-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "future_phase",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included",
      "plumbing": "future_phase"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "spelling",
  "rationale": "Plumbing is deferred to a later stage and is detected as future_phase without activating. HVAC is priced now and is the only active trade.",
  "spec_refs": [
    "2.2",
    "2.8"
  ],
  "text_ar": "نرجو تسعير أعمال التكيف للمرحلة الحالية. أما أعمال السباكة فتقع ضمن المرحلة التالية من العقد.",
  "text_en": "Please price the HVAC works for the current stage. The plumbing works fall under the next stage of the contract."
}'),
    ('{
  "adversarial": false,
  "bucket": "future_phase",
  "case_key": "F-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "maintenance",
        "disposition": "future_phase",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The maintenance stage belongs to a later contract, so a component override carries future_phase while the trade stays active. Future phase does not clarify, so no clarification is required.",
  "spec_refs": [
    "2.4",
    "2.7"
  ],
  "text_ar": "تركيب أنظمة التكييف ضمن هذا العقد، أما الصيانة فسيتم ترسيتها لاحقًا ضمن عقد تشغيل وصيانة منفصل.",
  "text_en": "The HVAC installation is in this contract; maintenance will be awarded later under a separate operation and maintenance contract."
}'),
    ('{
  "adversarial": false,
  "bucket": "future_phase",
  "case_key": "F-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "future_phase",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "electrical",
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included",
      "fire": "future_phase"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Fire is named directly and deferred to a later contract, which is future_phase and does not contribute. Electrical activates.",
  "spec_refs": [
    "2.1",
    "2.2"
  ],
  "text_ar": "أعمال الكهرباء مطلوبة الآن، وأعمال مكافحة الحريق مؤجلة إلى العقد الثاني.",
  "text_en": "Electrical is required now. The fire fighting works are deferred to the second contract."
}'),
    ('{
  "adversarial": true,
  "bucket": "future_phase",
  "case_key": "F-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "future_phase",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [
      "electrical"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "future_phase",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A later phase is a settled fact rather than an open question, so future_phase does not clarify and clarification_required stays false. The trade is still detected because the text gives evidence of it.",
  "spec_refs": [
    "2.2",
    "2.7",
    "2.8"
  ],
  "text_ar": "أعمال السباكة مُرسّاة علينا. أما أعمال الكهرباء فمجدولة لمرحلة لاحقة وليست جزءًا من هذه الترسية.",
  "text_en": "The plumbing works are awarded to us. The electrical works are scheduled for a later phase and are not part of this award."
}'),
    ('{
  "adversarial": false,
  "bucket": "existing_only",
  "case_key": "G-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "existing_only",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "existing_only"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An existing installation named together with a survey and a modification is existing_only, and the trade is active because there is work to do. No lifecycle split is stated, so a single complete_trade_scope row carries the trade disposition.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "نرجو معاينة أنظمة التكييف القائمة في المبنى واقتراح التعديلات المطلوبة.",
  "text_en": "Please survey the existing HVAC installation in the building and propose the modifications required."
}'),
    ('{
  "adversarial": false,
  "bucket": "existing_only",
  "case_key": "G-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "existing_only",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "existing_only"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "definite_article",
  "rationale": "An extension of an existing installation is a work verb, so fire is existing_only and contributes. Fire is named directly, which is the only route by which it enters a case.",
  "spec_refs": [
    "2.1",
    "2.3"
  ],
  "text_ar": "نحتاج إلى توسعة نظام إنذار الحريق القائم ليغطي طابق الميزانين الجديد.",
  "text_en": "We need the existing fire alarm system extended to cover the new mezzanine floor."
}'),
    ('{
  "adversarial": true,
  "bucket": "existing_only",
  "case_key": "G-003",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "ambiguous_trade",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "unknown",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [
      "electrical"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "unknown"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An existing installation mentioned with no action at all is unknown rather than existing_only, because nothing tells us whether any work is required. The unknown disposition clarifies and does not contribute.",
  "spec_refs": [
    "2.2",
    "2.3"
  ],
  "text_ar": "يوجد في المحل تركيبات كهربائية قائمة تركها المستأجر السابق.",
  "text_en": "The premises have an existing electrical installation left by the previous tenant."
}'),
    ('{
  "adversarial": false,
  "bucket": "existing_only",
  "case_key": "G-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "maintenance",
        "disposition": "existing_only",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "existing_only"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Maintenance of an existing installation is a service obligation and therefore existing_only, which contributes. The text addresses the maintenance stage only, so that single component row is stated and the rest inherit.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "نطلب صيانة مضخات المياه المبردة القائمة بموجب عقد سنوي.",
  "text_en": "We require the existing chilled water pumps to be maintained under an annual contract."
}'),
    ('{
  "adversarial": false,
  "bucket": "existing_only",
  "case_key": "G-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": "ambiguous_trade",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "unknown",
        "trade": "elv"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "existing_only",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "elv",
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "unknown",
      "plumbing": "existing_only"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Replacement is a work verb so plumbing is existing_only and active, while the intercom is mentioned with no action and is therefore unknown. The unknown disposition drives clarification with reason ambiguous_trade.",
  "spec_refs": [
    "2.3",
    "2.7"
  ],
  "text_ar": "يجب استبدال شبكة تغذية المياه القائمة في كامل العمارة، كما يوجد نظام اتصال داخلي قائم في المدخل.",
  "text_en": "The existing water supply pipework is to be replaced throughout the block, and there is also an existing intercom system in the lobby."
}'),
    ('{
  "adversarial": true,
  "bucket": "existing_only",
  "case_key": "G-006",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "ambiguous_trade",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "unknown",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [
      "elv"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "unknown"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An existing installation with no work verb attached is unknown, and the absence of an instruction confirms that no action has been requested. The trade is detected but does not activate.",
  "spec_refs": [
    "2.3",
    "2.8"
  ],
  "text_ar": "توجد مسارات كابلات قائمة للتيار الخفيف داخل فراغ السقف نفذها المقاول السابق، ولم تصدر أي تعليمات بشأنها.",
  "text_en": "There is existing ELV containment installed in the ceiling void by the previous contractor, and no instruction has been issued about it."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_exclusion_exception",
  "case_key": "H-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "excluded",
      "plumbing": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An exception clause attached to an umbrella statement is more specific and defeats the umbrella for its own subject, so electrical is included while the other two core trades stay excluded. The umbrella never reaches fire or ELV.",
  "spec_refs": [
    "2.1",
    "2.5"
  ],
  "text_ar": "أعمال الميكانيكا والكهرباء والصحية مستثناة من نطاقنا، باستثناء أعمال الكهرباء التي سنقوم بتنفيذها.",
  "text_en": "The MEP works are excluded from our scope, except the electrical works which we will carry out."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_exclusion_exception",
  "case_key": "H-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "fire"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "fire",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv"
    ],
    "trade_dispositions": {
      "electrical": "excluded",
      "fire": "included",
      "hvac": "excluded",
      "plumbing": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Fire enters the case because it is named in an explicit exception attached to the umbrella statement, which is the permitted route. The three core trades are removed with no other party identified and are therefore excluded.",
  "spec_refs": [
    "2.1",
    "2.3",
    "2.5"
  ],
  "text_ar": "حزمة الميكانيكا والكهرباء والصحية ليست معنا، والاستثناء الوحيد هو أعمال مكافحة الحريق التي سنقوم بتنفيذها.",
  "text_en": "The MEP package is not with us; the only exception is the fire fighting works, which we will deliver."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_exclusion_exception",
  "case_key": "H-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "by_others",
      "hvac": "by_others",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "plural",
  "rationale": "The umbrella removal identifies a responsible party, so the two core trades it still governs are by_others rather than excluded. The exception defeats the umbrella for plumbing only.",
  "spec_refs": [
    "2.3",
    "2.5"
  ],
  "text_ar": "نطاق أعمال الميكانيكا والكهرباء والصحية مع الفرق الداخلية للمقاول الرئيسي، باستثناء أعمال السباكة التي تخصنا.",
  "text_en": "The MEP scope is with the main contractor''s in-house teams, except the plumbing works which are ours."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_exclusion_exception",
  "case_key": "H-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "elv"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "elv"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "elv",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "excluded",
      "elv": "included",
      "hvac": "excluded",
      "plumbing": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "ELV is named in an explicit exception attached to the umbrella, which is how a non-core trade enters a case. The umbrella itself removes only the three core trades and identifies no other party.",
  "spec_refs": [
    "2.1",
    "2.3",
    "2.5"
  ],
  "text_ar": "أعمال الميكانيكا والكهرباء والصحية خارج نطاق أعمالنا، وتُستثنى أنظمة التيار الخفيف والأمن التي تبقى معنا.",
  "text_en": "MEP is outside our scope of works. ELV and security are the exception and remain with us."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_exclusion_exception",
  "case_key": "H-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "electrical"
      },
      {
        "component": "maintenance",
        "disposition": "existing_only",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "excluded",
      "hvac": "existing_only",
      "plumbing": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The exception names an existing installation with a maintenance obligation, so HVAC is existing_only and active while the umbrella exclusion still governs the other two core trades. The exception addresses the maintenance stage, which states a split for that trade.",
  "spec_refs": [
    "2.3",
    "2.4",
    "2.5"
  ],
  "text_ar": "أعمال الميكانيكا والكهرباء والصحية مستثناة، باستثناء صيانة نظام التكييف القائم التي سنستمر في تقديمها.",
  "text_en": "The MEP works are excluded, except the maintenance of the existing HVAC system which we will continue to provide."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_exclusion_exception",
  "case_key": "H-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "fire"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "fire",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "fire": "included",
      "hvac": "excluded",
      "plumbing": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Two subjects are carved out of the umbrella by the same exception clause, one core and one non-core, and both are included. ELV is never named and is not reached by the umbrella.",
  "spec_refs": [
    "2.1",
    "2.5"
  ],
  "text_ar": "جميع أعمال الميكانيكا والكهرباء والصحية مستثناة من هذا العرض عدا أعمال الكهرباء وأعمال مكافحة الحريق.",
  "text_en": "All MEP works are excluded from this offer apart from the electrical works and the fire fighting works."
}'),
    ('{
  "adversarial": true,
  "bucket": "umbrella_exclusion_exception",
  "case_key": "H-007",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "excluded",
      "hvac": "excluded",
      "plumbing": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A completeness modifier qualifying an umbrella services term widens it across the three core trades only and never reaches fire or ELV. With no exception and no other party identified, all three are excluded and no trade is active.",
  "spec_refs": [
    "2.1",
    "2.3",
    "2.9"
  ],
  "text_ar": "أعمال الميكانيكا والكهرباء والصحية بكاملها مستثناة من عرضنا.",
  "text_en": "The MEP works in their entirety are excluded from our proposal."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_inclusion_exclusion",
  "case_key": "I-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "included",
      "plumbing": "by_others"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The modifier qualifies the umbrella services term in the same clause and so widens it across the core three, and the exception then carves plumbing out to an identified party. Fire and ELV are not reached.",
  "spec_refs": [
    "2.1",
    "2.3",
    "2.5"
  ],
  "text_ar": "نطاق أعمال الميكانيكا والكهرباء والصحية بالكامل مشمول، باستثناء أعمال السباكة التي ينفذها مقاول المطوّر.",
  "text_en": "The complete MEP scope is included, except the plumbing works which are by the developer''s own contractor."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_inclusion_exclusion",
  "case_key": "I-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac",
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "excluded",
      "hvac": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A trade-level statement about a named trade defeats the umbrella for that trade, so electrical is excluded while the other core trades stay included. No other party is identified for the carve-out.",
  "spec_refs": [
    "2.3",
    "2.5"
  ],
  "text_ar": "سنقوم بتنفيذ خدمات الميكانيكا والكهرباء والصحية كاملة للبرج، إلا أن أعمال الكهرباء ليست جزءًا مما سننفذه.",
  "text_en": "We will deliver the full MEP services for the tower, but the electrical works are not part of what we will deliver."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_inclusion_exclusion",
  "case_key": "I-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "supply",
        "disposition": "client_supplied",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The exception concerns the equipment provided by the counterparty, which is client_supplied on the supply stage rather than a removal of the trade. HVAC therefore stays active with one non-contributing component.",
  "spec_refs": [
    "2.3",
    "2.4",
    "2.5"
  ],
  "text_ar": "نطاق أعمال الميكانيكا والكهرباء والصحية لنا، باستثناء أن معدات التكييف نفسها سيوفرها العميل.",
  "text_en": "The MEP scope is ours, except that the HVAC equipment itself will be provided by the client."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_inclusion_exclusion",
  "case_key": "I-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "fire",
      "hvac",
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "fire"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "fire",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "fire": "included",
      "hvac": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "proclitic",
  "rationale": "The umbrella covers the three core trades and fire is added by being named directly, so four trades are included. ELV is neither named nor carved out and is not detected.",
  "spec_refs": [
    "2.1",
    "2.8"
  ],
  "text_ar": "نطاقنا يشمل خدمات الميكانيكا والكهرباء والصحية كاملة، وبالإضافة إلى ذلك أعمال مكافحة الحريق.",
  "text_en": "Our scope covers the full MEP services and, in addition, the fire fighting works."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_inclusion_exclusion",
  "case_key": "I-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "future_phase",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "included",
      "plumbing": "future_phase"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The exception assigns plumbing to a later phase, which is future_phase and does not contribute, while the umbrella keeps the other two core trades included. Future phase is not a clarifying disposition.",
  "spec_refs": [
    "2.2",
    "2.5"
  ],
  "text_ar": "حزمة الميكانيكا والكهرباء والصحية بأكملها معنا لهذا المبنى، باستثناء أعمال السباكة التي تبدأ في المرحلة القادمة.",
  "text_en": "The whole MEP package is with us for this building, except the plumbing works which start in the next phase."
}'),
    ('{
  "adversarial": false,
  "bucket": "umbrella_inclusion_exclusion",
  "case_key": "I-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac",
      "plumbing"
    ],
    "clarification_reason": "optional_pending_decision",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "optional",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "optional",
      "hvac": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The exception makes electrical an undecided option, which never activates and always clarifies, while the umbrella keeps the other core trades included and active. The open question decides whether a trade is delivered at all.",
  "spec_refs": [
    "2.2",
    "2.5",
    "2.9"
  ],
  "text_ar": "خدمات الميكانيكا والكهرباء والصحية بالكامل مشمولة في سعرنا، مع عرض أعمال الكهرباء كخيار يمكن للعميل قبوله أو تركه.",
  "text_en": "The complete MEP services are included in our price, with the electrical works offered as an option the client may take or leave."
}'),
    ('{
  "adversarial": true,
  "bucket": "umbrella_inclusion_exclusion",
  "case_key": "I-007",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "by_others",
        "trade": "electrical"
      },
      {
        "component": "authority_approvals",
        "disposition": "by_others",
        "trade": "hvac"
      },
      {
        "component": "authority_approvals",
        "disposition": "by_others",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The carve-out is a component-level statement and therefore overrides only the approvals stage of each core trade, leaving every other stage to inherit included. All three trades stay active because their trade-level dispositions contribute.",
  "spec_refs": [
    "2.4",
    "2.5"
  ],
  "text_ar": "نطاق الميكانيكا والكهرباء والصحية بالكامل لنا، باستثناء موافقات الجهات التي سيقدمها الاستشاري للخدمات الثلاث.",
  "text_en": "The full MEP scope is ours, except the authority approvals, which the consultant will submit for all three services."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "design",
        "disposition": "by_others",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A component-level statement assigns the design stage to an identified party, so that stage is by_others and every unstated stage inherits included. The trade remains active.",
  "spec_refs": [
    "2.4",
    "2.5"
  ],
  "text_ar": "تصميم أنظمة التكييف يقوم به الاستشاري المعيّن، ونتولى نحن الأعمال بدءًا من المخططات التنفيذية.",
  "text_en": "The HVAC design is by the appointed consultant; we take the works forward from the shop drawings onward."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "commissioning",
        "disposition": "excluded",
        "trade": "electrical"
      },
      {
        "component": "design",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "supply",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "testing",
        "disposition": "excluded",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Five lifecycle stages are addressed explicitly, so five component rows are stated and complete_trade_scope must not appear. The trade contributes and not every one of the nine components is stated, so it stays active.",
  "spec_refs": [
    "2.4"
  ],
  "text_ar": "بالنسبة لأعمال الكهرباء سنقوم بالتصميم والتوريد والتركيب، أما الاختبار والتشغيل والتسليم فليسا ضمن نطاقنا.",
  "text_en": "For the electrical works we will design, supply and install. Testing and commissioning are not part of our scope."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "excluded",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "alef_variant",
  "rationale": "The approvals stage is removed with no other party identified, so it is excluded, and the remaining stages inherit the trade disposition. A single non-contributing component does not deactivate a contributing trade.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "اعمال السباكة ضمن نطاقنا، وموافقات الجهات مستثناة.",
  "text_en": "The plumbing works are in our scope; the authority approvals are excluded."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "elv"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "coordination",
        "disposition": "included",
        "trade": "elv"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "elv"
      },
      {
        "component": "supply",
        "disposition": "client_supplied",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Counterparty supply sits on the supply stage as client_supplied while installation and coordination are ours. The trade contributes and is active.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "سيقوم العميل بتوريد أجهزة التيار الخفيف. وسنقوم نحن بتركيبها والتنسيق مع باقي التخصصات في الموقع.",
  "text_en": "The client will supply the ELV equipment. We will install it and coordinate with the other trades on site."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "fire"
      },
      {
        "component": "maintenance",
        "disposition": "future_phase",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Maintenance is placed under a later contract, so that component carries future_phase while installation stays included. Future phase does not clarify, so clarification is not required.",
  "spec_refs": [
    "2.2",
    "2.4"
  ],
  "text_ar": "تركيب أنظمة مكافحة الحريق ضمن هذه الحزمة، ولا تبدأ الصيانة إلا بعد انتهاء فترة الضمان بموجب عقد لاحق.",
  "text_en": "The fire fighting installation is in this package; maintenance starts only after the defects liability period under a later contract."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "commissioning",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "coordination",
        "disposition": "excluded",
        "trade": "hvac"
      },
      {
        "component": "testing",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Three lifecycle stages are addressed, two contributing and one removed with no party identified. The trade-level disposition contributes, so the trade is active with one non-contributing component.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "سنقوم باختبار وتشغيل وتسليم نظام التكييف. أما التنسيق مع مقاول التشطيبات الداخلية فمستثنى من نطاقنا.",
  "text_en": "We will test and commission the HVAC system. Coordination with the interior contractor is excluded from our scope."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-007",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": "ambiguous_trade",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "design",
        "disposition": "unknown",
        "trade": "electrical"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The design stage is named but its disposition cannot be determined from the text, which is unknown at component level and clarifies on its own. The trade itself is clean and active, and the answer changes the quoted component scope.",
  "spec_refs": [
    "2.2",
    "2.4",
    "2.7"
  ],
  "text_ar": "أعمال الكهرباء مُرسّاة علينا. ولم توضّح المستندات ما إذا كان التصميم التفصيلي مشمولًا في الترسية.",
  "text_en": "The electrical works are awarded to us. The documents do not state whether the detailed design is included in the award."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-008",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": "ambiguous_trade",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "design",
        "disposition": "unknown",
        "trade": "plumbing"
      },
      {
        "component": "installation",
        "disposition": "existing_only",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "plumbing": "existing_only"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Re-routing an existing network is a work verb, so the trade is existing_only and active, while the design stage is named without a determinable disposition and is unknown. The component-level unknown drives clarification with reason ambiguous_trade.",
  "spec_refs": [
    "2.3",
    "2.4",
    "2.7"
  ],
  "text_ar": "يجب إعادة توجيه شبكة الصرف القائمة. ولم يُذكر في أي موضع ما إذا كان تصميم إعادة التوجيه علينا أم على الاستشاري.",
  "text_en": "The existing drainage network is to be re-routed. Whether the re-routing design sits with us or with the consultant is not stated anywhere."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-009",
  "documents": [],
  "expect": {
    "active_trades": [
      "elv"
    ],
    "clarification_reason": "optional_pending_decision",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "design",
        "disposition": "optional",
        "trade": "elv"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The design stage carries an undecided option while the installation stage is included, so the trade is active and clarification is still required. The reason is optional_pending_decision because no earlier trigger in the precedence order applies.",
  "spec_refs": [
    "2.4",
    "2.7"
  ],
  "text_ar": "تركيب أنظمة التيار الخفيف مشمول. وتصميم الأنظمة معروض كبند اختياري حسب رغبتكم.",
  "text_en": "The ELV installation is included. The system design is offered as an option at your discretion."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-010",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "commissioning",
        "disposition": "by_others",
        "trade": "fire"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "fire"
      },
      {
        "component": "supply",
        "disposition": "included",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The commissioning stage is assigned to an identified third party, so it is by_others while supply and installation stay included. The trade contributes and is active.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "سنقوم بتوريد وتركيب نظام مكافحة الحريق، على أن يتولى المفتش المعتمد من طرف ثالث أعمال التشغيل والتسليم.",
  "text_en": "We will supply and install the fire fighting system; commissioning will be carried out by the approved third-party inspector."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-011",
  "documents": [],
  "expect": {
    "active_trades": [
      "elv"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "commissioning",
        "disposition": "included",
        "trade": "elv"
      },
      {
        "component": "maintenance",
        "disposition": "excluded",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Two lifecycle stages are addressed, one included and one removed with no party identified. The trade-level disposition contributes, so the trade remains active.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "أعمال التيار الخفيف بما فيها التشغيل والتسليم تخصنا. والصيانة بعد التسليم مستثناة.",
  "text_en": "The ELV works including commissioning are ours. Maintenance after handover is excluded."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-012",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "by_others",
        "trade": "electrical"
      },
      {
        "component": "coordination",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "supply",
        "disposition": "included",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": true,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The utility submission is a component-level statement assigning the approvals stage to an identified party, so it is by_others. Supply and coordination are ours and the remaining stages inherit included.",
  "spec_refs": [
    "2.3",
    "2.4",
    "2.5"
  ],
  "text_ar": "بالنسبة لأعمال الكهرباء نقوم بتوريد المواد والتنسيق في الموقع، أما تقديم المعاملة إلى هيئة كهرباء ومياه دبي فيتولاه استشاري العميل.",
  "text_en": "For the electrical works we supply the materials and coordinate on site; the DEWA submission is handled by the client''s consultant."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-013",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": "ambiguous_trade",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "commissioning",
        "disposition": "unknown",
        "trade": "hvac"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The commissioning stage is named but undeterminable, which is unknown at component level and requires clarification even though the trade is clean and active. Resolving it changes what a supplier would be told to quote.",
  "spec_refs": [
    "2.2",
    "2.4",
    "2.9"
  ],
  "text_ar": "أعمال التكييف معنا. ولا يوضح طلب العرض ما إذا كان التشغيل والتسليم ضمن هذه الحزمة أم يُعالج بشكل منفصل.",
  "text_en": "The HVAC works are with us. The enquiry does not say whether commissioning is inside this package or handled separately."
}'),
    ('{
  "adversarial": false,
  "bucket": "component_split",
  "case_key": "J-014",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": "ambiguous_trade",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "optional",
        "trade": "elv"
      },
      {
        "component": "authority_approvals",
        "disposition": "unknown",
        "trade": "plumbing"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "elv",
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [
      "elv"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "optional",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Two clarifying dispositions co-occur at different levels, and the precedence order is computed over trade and component dispositions together rather than by level, so the component-level unknown outranks the trade-level option. The reason is therefore ambiguous_trade and plumbing stays active.",
  "spec_refs": [
    "2.4",
    "2.7"
  ],
  "text_ar": "أعمال السباكة تخصنا، غير أن المستندات لا توضح ما إذا كانت موافقات الجهات مشمولة. أما حزمة التيار الخفيف فمعروضة بشكل منفصل كخيار يمكن للعميل رفضه.",
  "text_en": "The plumbing works are ours, though the documents do not say whether the authority approvals are included. The ELV package is separately offered as an option the client may still decline."
}'),
    ('{
  "adversarial": false,
  "bucket": "equal_specificity_conflict",
  "case_key": "K-001",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "conflict",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "conflicted",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade",
      "scope_conflict_unresolved"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "conflicted"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Two trade-level statements about the same named trade cannot both hold, and neither is more specific, so the disposition is conflicted and no positional tie-break may be applied. The conflict raises its own blocker and clarification with reason conflict.",
  "spec_refs": [
    "2.5",
    "2.7",
    "2.9"
  ],
  "text_ar": "ينص البند الثالث من طلب العرض على أن أعمال الكهرباء ضمن نطاقنا، بينما ينص البند التاسع على أن أعمال الكهرباء ليست جزءًا من نطاقنا.",
  "text_en": "Clause 3 of the enquiry states that the electrical works are included in our scope, and clause 9 states that the electrical works are not part of our scope."
}'),
    ('{
  "adversarial": false,
  "bucket": "equal_specificity_conflict",
  "case_key": "K-002",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "conflict",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "conflicted",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade",
      "scope_conflict_unresolved"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "plumbing": "conflicted"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "definite_article",
  "rationale": "An inclusion and an assignment to another party sit at the same trade level and contradict each other, which is conflicted rather than a choice between the two readings. The trade is detected and does not activate.",
  "spec_refs": [
    "2.5",
    "2.8"
  ],
  "text_ar": "يذكر الخطاب المرفق أن أعمال السباكة تخصنا، بينما يسند جدول توزيع النطاق أعمال السباكة إلى المقاول الرئيسي.",
  "text_en": "The covering letter says the plumbing works are ours, while the scope matrix assigns the plumbing works to the main contractor."
}'),
    ('{
  "adversarial": false,
  "bucket": "equal_specificity_conflict",
  "case_key": "K-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": "conflict",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "conflicted",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "scope_conflict_unresolved"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "conflicted"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The contradiction sits on HVAC at trade level and produces conflicted, while electrical is unaffected and remains active. The conflict blocker is raised even though a trade is active.",
  "spec_refs": [
    "2.5",
    "2.9"
  ],
  "text_ar": "أعمال الكهرباء تخصنا. أما التكييف فيذكر طلب العرض في موضع أنه مشمول وفي موضع آخر أنه مستثنى.",
  "text_en": "The electrical works are ours. For HVAC the enquiry states in one place that it is included and in another that it is excluded."
}'),
    ('{
  "adversarial": false,
  "bucket": "equal_specificity_conflict",
  "case_key": "K-004",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "conflict",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "conflicted",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "conflicted",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "conflicted",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade",
      "scope_conflict_unresolved"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "conflicted",
      "hvac": "conflicted",
      "plumbing": "conflicted"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Two umbrella statements at the same level contradict each other, so all three core trades are conflicted and none activates. The umbrella never reaches fire or ELV even when contradicted.",
  "spec_refs": [
    "2.1",
    "2.5"
  ],
  "text_ar": "يذكر خطاب الترسية أن أعمال الميكانيكا والكهرباء والصحية ضمن نطاقنا، ثم يذكر الخطاب نفسه لاحقًا أنها ليست ضمن نطاقنا.",
  "text_en": "The award letter states that the MEP works are in our scope; the same letter later states that the MEP works are not in our scope."
}'),
    ('{
  "adversarial": false,
  "bucket": "equal_specificity_conflict",
  "case_key": "K-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": "conflict",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "conflicted",
        "trade": "plumbing"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "scope_conflict_unresolved"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Two component-level statements about the same stage of the same trade contradict each other, so that component is conflicted while the trade stays clean and active. A conflict at component level raises the same blocker and the same clarification reason as one at trade level.",
  "spec_refs": [
    "2.5",
    "2.7",
    "2.9"
  ],
  "text_ar": "أعمال السباكة تخصنا. تنص المواصفات على أن موافقات الجهات الخاصة بالسباكة ضمن نطاقنا، بينما يذكر جدول النطاق أن الموافقات نفسها مستثناة.",
  "text_en": "The plumbing works are ours. The specification says the authority approvals for the plumbing are in our scope; the scope matrix says the same approvals are excluded."
}'),
    ('{
  "adversarial": false,
  "bucket": "equal_specificity_conflict",
  "case_key": "K-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": "conflict",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "coordination",
        "disposition": "conflicted",
        "trade": "hvac"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "scope_conflict_unresolved"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The contradiction sits entirely on the coordination stage at equal specificity, so that component is conflicted and the trade remains active. The unresolved contradiction still makes the supplier brief incomplete.",
  "spec_refs": [
    "2.5",
    "2.9"
  ],
  "text_ar": "أعمال التكييف مُرسّاة علينا. أحد البنود يجعل التنسيق في الموقع من مسؤوليتنا وبند آخر ينص على أن التنسيق في الموقع ليس من مسؤوليتنا.",
  "text_en": "The HVAC works are awarded to us. One clause makes site coordination our responsibility and another clause states that site coordination is not ours."
}'),
    ('{
  "adversarial": false,
  "bucket": "equal_specificity_conflict",
  "case_key": "K-007",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": "conflict",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "fire"
      },
      {
        "component": "maintenance",
        "disposition": "conflicted",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "scope_conflict_unresolved"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Both statements address the maintenance stage of a named trade at the same specificity and cannot both hold, so the component is conflicted. Fire is active while the conflict blocker and the conflict reason are both raised.",
  "spec_refs": [
    "2.5",
    "2.7"
  ],
  "text_ar": "أعمال مكافحة الحريق ضمن نطاقنا. تذكر المناقصة أن الصيانة مشمولة لمدة سنة، بينما يذكر الملحق أن الصيانة غير مشمولة إطلاقًا.",
  "text_en": "The fire fighting works are in our scope. The tender says maintenance is included for one year and the annexure says maintenance is not included at all."
}'),
    ('{
  "adversarial": false,
  "bucket": "equal_specificity_conflict",
  "case_key": "K-008",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": "conflict",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "unknown",
        "trade": "elv"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "testing",
        "disposition": "conflicted",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "elv",
      "hvac"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "scope_conflict_unresolved"
    ],
    "must_not_activate": [
      "elv"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "unknown",
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A conflict sitting on a component outranks an unknown sitting on a trade, because the precedence order is applied across both levels at once, so the reason is conflict and the conflict blocker is raised. HVAC remains active while the contradiction inside its scope stays unresolved.",
  "spec_refs": [
    "2.5",
    "2.7",
    "2.9"
  ],
  "text_ar": "أعمال التكييف معنا، لكن أحد البنود يجعل الاختبار من مسؤوليتنا وبندًا آخر ينص على أن الاختبار ليس من مسؤوليتنا. كما يشير طلب العرض إلى نظام اتصال داخلي قائم دون أي تعليمات بشأنه.",
  "text_en": "The HVAC works are with us, but one clause makes the testing our responsibility and another states that the testing is not ours. The enquiry also mentions an existing intercom system with no instruction attached to it."
}'),
    ('{
  "adversarial": false,
  "bucket": "clause_boundary",
  "case_key": "L-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The modifier qualifies a trade term inside its own clause, with no boundary between them, so it reaches that term and widens the electrical scope. It confers no trade meaning of its own and reaches no other trade.",
  "spec_refs": [
    "2.3",
    "2.6"
  ],
  "text_ar": "نطاق أعمال الكهرباء الكامل ضمن حزمتنا في هذا المشروع.",
  "text_en": "The complete electrical scope is in our package for this project."
}'),
    ('{
  "adversarial": true,
  "bucket": "clause_boundary",
  "case_key": "L-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Sentence-final punctuation ends the clause, so the completeness modifier in the second sentence binds to a document set and cannot reach the trade term in the first. A modifier attached to a non-services noun carries no trade meaning at all.",
  "spec_refs": [
    "2.3",
    "2.6"
  ],
  "text_ar": "نرجو تسعير نظام إنذار الحريق. والمجموعة الكاملة من مخططات ما بعد التنفيذ غير مطلوبة منكم.",
  "text_en": "Please price the fire alarm system. The complete set of as-built drawings is not required from you."
}'),
    ('{
  "adversarial": true,
  "bucket": "clause_boundary",
  "case_key": "L-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The modifier qualifies an umbrella services term within the same clause and therefore widens it, but widening an umbrella still reaches the three core trades only. Fire and ELV are not named and must not be detected.",
  "spec_refs": [
    "2.1",
    "2.3",
    "2.6"
  ],
  "text_ar": "نطاق الميكانيكا والكهرباء والصحية بأكمله لنا في هذا البرج.",
  "text_en": "The entire MEP scope is ours on this tower."
}'),
    ('{
  "adversarial": true,
  "bucket": "clause_boundary",
  "case_key": "L-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "plumbing"
    ],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An adversative conjunction closes the clause, so neither the modifier nor the identified other party in the second clause can reach the trade term in the first. HVAC therefore stays included and active.",
  "spec_refs": [
    "2.3",
    "2.5",
    "2.6"
  ],
  "text_ar": "سنقوم بتسعير أعمال التكييف، لكن حزمة الأعمال المدنية بأكملها مع مقاول آخر.",
  "text_en": "We will price the HVAC works, but the whole civil package is with another contractor."
}'),
    ('{
  "adversarial": true,
  "bucket": "clause_boundary",
  "case_key": "L-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A semicolon is a clause boundary, so the modifier and the exclusion in the second clause bind to the documentation and not to the trade named in the first. Electrical remains included with no component split stated.",
  "spec_refs": [
    "2.3",
    "2.6"
  ],
  "text_ar": "أعمال الكهرباء مشمولة؛ وكامل مستندات الضمان مستثناة من التزاماتنا.",
  "text_en": "Electrical is included; the entire warranty documentation is excluded from our obligations."
}'),
    ('{
  "adversarial": false,
  "bucket": "clause_boundary",
  "case_key": "L-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac"
    ],
    "trade_dispositions": {
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "ta_marbuta",
  "rationale": "The modifier sits beside the trade term inside a single clause with no boundary between them, so it binds and widens that trade. The second modifier attaches to the building rather than to any services term and carries no trade meaning.",
  "spec_refs": [
    "2.3",
    "2.6"
  ],
  "text_ar": "أعمال السباكة كامله ضمن نطاقنا للعمارة بأكملها.",
  "text_en": "The plumbing works in full are within our scope for the whole block."
}'),
    ('{
  "adversarial": false,
  "bucket": "clause_boundary",
  "case_key": "L-007",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "clarification_reason": "ambiguous_scope_binding",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac",
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "elv",
      "fire"
    ],
    "trade_dispositions": {
      "electrical": "included",
      "hvac": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "All three trades are named and included, but the trailing modifier sits inside one clause with a list and may bind to the final item or to the whole list. That binding is genuinely ambiguous, which requires clarification with reason ambiguous_scope_binding.",
  "spec_refs": [
    "2.6",
    "2.7"
  ],
  "text_ar": "نرجو تسعير أعمال التكييف والكهرباء والسباكة بالكامل.",
  "text_en": "Kindly quote the HVAC, electrical and plumbing works in full."
}'),
    ('{
  "adversarial": false,
  "bucket": "mixed_language",
  "case_key": "M-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "plumbing"
    ],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": true,
  "morphology_variant": null,
  "rationale": "Each language carries the other''s technical term for the same trade, and both texts state the same scope at the same specificity. The trade is named and included with no lifecycle split stated.",
  "spec_refs": [
    "2.1",
    "2.2"
  ],
  "text_ar": "نرجو تسعير أعمال الـ HVAC للفيلا بما في ذلك الـ ducting والمخارج.",
  "text_en": "Kindly quote the التكييف والتهوية works for the villa, including the ducting and the diffusers."
}'),
    ('{
  "adversarial": false,
  "bucket": "mixed_language",
  "case_key": "M-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "included",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": true,
  "morphology_variant": null,
  "rationale": "Fire is named directly in both texts and the approvals stage is addressed explicitly, which states a split. A borrowed authority name does not change the trade reading.",
  "spec_refs": [
    "2.1",
    "2.4"
  ],
  "text_ar": "نحتاج تسعير نطاق مكافحة الحريق مع موافقة الـ Civil Defence.",
  "text_en": "We need the fire fighting scope priced together with the الدفاع المدني approval."
}'),
    ('{
  "adversarial": false,
  "bucket": "mixed_language",
  "case_key": "M-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "elv"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "elv": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": true,
  "morphology_variant": null,
  "rationale": "The ELV trade is named in both texts through the other language''s term and is in scope, so it is included and active. Naming ELV subject matter does not reach the electrical trade.",
  "spec_refs": [
    "2.1",
    "2.2"
  ],
  "text_ar": "حزمة الـ ELV، وتشمل الـ CCTV وأنظمة الـ access control، ضمن نطاق عملنا.",
  "text_en": "The أنظمة التيار الخفيف package, CCTV and access control included, is within our scope."
}'),
    ('{
  "adversarial": true,
  "bucket": "mixed_language",
  "case_key": "M-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included",
      "plumbing": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": true,
  "morphology_variant": null,
  "rationale": "A borrowed trade term is still a trade term, so plumbing is detected and removed with no other party identified, which is excluded. Electrical is included and active.",
  "spec_refs": [
    "2.3",
    "2.8"
  ],
  "text_ar": "أعمال الـ plumbing مستثناة من عرضنا، والكهرباء فقط تخصنا.",
  "text_en": "The السباكة works are excluded from our offer; only the electrical is ours."
}'),
    ('{
  "adversarial": false,
  "bucket": "mixed_language",
  "case_key": "M-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "supply",
        "disposition": "client_supplied",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": true,
  "morphology_variant": "plural",
  "rationale": "The borrowed equipment terms are pluralised in the host language and still identify the HVAC trade, whose supply stage is client_supplied and whose installation stage is included. The trade contributes and stays active.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "سيتم توريد الـ FCUs و الـ AHUs من قبل العميل، وسنقوم نحن بالـ installation فقط.",
  "text_en": "The وحدات المناولة will be supplied by the client; we will carry out the التركيب only."
}'),
    ('{
  "adversarial": false,
  "bucket": "mixed_language",
  "case_key": "M-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "included",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": true,
  "mixed_language": true,
  "morphology_variant": null,
  "rationale": "The electrical trade is named in both texts and the utility submission addresses the approvals stage, which states a split for that trade. Both stated components carry the trade disposition.",
  "spec_refs": [
    "2.4"
  ],
  "text_ar": "نرجو تضمين الـ distribution boards ضمن نطاق الكهرباء وتأكيد أن تقديم معاملة الـ DEWA لديكم.",
  "text_en": "Please include the لوحات التوزيع in the electrical scope and confirm the DEWA submission is with you."
}'),
    ('{
  "adversarial": false,
  "bucket": "gulf_phrasing",
  "case_key": "N-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": true,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Local building-typology and correspondence register do not change the reading, so HVAC is included and the municipality submission states the approvals stage. That split replaces the complete_trade_scope row.",
  "spec_refs": [
    "2.4"
  ],
  "text_ar": "نرجو الرد بأفضل عرض لأعمال التكييف لفيلا أرضي وأول في الورقاء، بما في ذلك تقديم المخططات التنفيذية إلى البلدية.",
  "text_en": "Kindly revert with your best offer for the HVAC works for a villa G+1 in Al Warqa, including the municipality shop drawing submission."
}'),
    ('{
  "adversarial": false,
  "bucket": "gulf_phrasing",
  "case_key": "N-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "included",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": true,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The utility connection process addresses the approvals stage of a named trade, which states a split carrying the trade disposition. No other trade is named.",
  "spec_refs": [
    "2.4"
  ],
  "text_ar": "لمشروع العين نحتاج تسعير أعمال الكهرباء، على أن تكون موافقات التوصيل من شركة التوزيع مشمولة.",
  "text_en": "For the Al Ain project we need the electrical works quoted, and the distribution company connection approvals are to be included."
}'),
    ('{
  "adversarial": false,
  "bucket": "gulf_phrasing",
  "case_key": "N-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "maintenance",
        "disposition": "existing_only",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "plumbing": "existing_only"
    }
  },
  "gulf_phrasing": true,
  "mixed_language": false,
  "morphology_variant": "plural",
  "rationale": "An existing installation named with a servicing obligation is existing_only and the trade is active because there is work to do. The text addresses the maintenance stage only.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "سكن العمال في القوز يحتاج إلى صيانة خزانات المياه والمضخات القائمة قبل الصيف.",
  "text_en": "The labour accommodation in Al Quoz needs the existing water tanks and pumps serviced before the summer."
}'),
    ('{
  "adversarial": false,
  "bucket": "gulf_phrasing",
  "case_key": "N-004",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "authority_approvals",
        "disposition": "included",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": true,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Fire is named directly and the statutory certificate addresses the approvals stage of that trade. Both are in scope, so the trade is included and active.",
  "spec_refs": [
    "2.1",
    "2.4"
  ],
  "text_ar": "نرجو إفادتنا بسعركم لأعمال مكافحة الحريق وتأكيد قدرتكم على استخراج شهادة عدم ممانعة من الدفاع المدني.",
  "text_en": "Kindly advise your price for the fire fighting works and confirm you can obtain the Civil Defence no-objection certificate."
}'),
    ('{
  "adversarial": false,
  "bucket": "gulf_phrasing",
  "case_key": "N-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "elv"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "elv": "included"
    }
  },
  "gulf_phrasing": true,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The enquiry names one trade and restricts itself to it, so only that trade is detected and it is included. The local building typology carries no additional trade meaning.",
  "spec_refs": [
    "2.1",
    "2.8"
  ],
  "text_ar": "لملحق المجلس في فيلا العائلة نحتاج كاميرات مراقبة ونظام اتصال داخلي، نطاق التيار الخفيف فقط.",
  "text_en": "For the majlis extension at the family villa we need CCTV and intercom, ELV scope only."
}'),
    ('{
  "adversarial": false,
  "bucket": "gulf_phrasing",
  "case_key": "N-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "plumbing"
    ],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": true,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Commercial terms in the second clause are not scope statements and add no trade evidence, so only the named trade is detected. HVAC is included and active.",
  "spec_refs": [
    "2.6",
    "2.8"
  ],
  "text_ar": "نرجو تسعير أعمال التكييف للمستودع في القوز؛ شروط الدفع 30 يومًا واحتجاز 5 بالمئة حسب المتبع لدينا.",
  "text_en": "Kindly quote the HVAC works for the warehouse in Al Quoz; payment terms 30 days and 5 percent retention as per our standard practice."
}'),
    ('{
  "adversarial": false,
  "bucket": "arabic_morphology",
  "case_key": "O-001",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "plumbing"
    ],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "definite_article",
  "rationale": "The trade term appears with the definite article and is requested in scope, so HVAC is included. Orthographic form does not change the disposition.",
  "spec_refs": [
    "2.1",
    "2.2"
  ],
  "text_ar": "أعمال التكييف للمحل في ديرة مطلوبة مع أفضل سعر لديكم.",
  "text_en": "The air conditioning works for the shop in Deira are required with your best price."
}'),
    ('{
  "adversarial": false,
  "bucket": "arabic_morphology",
  "case_key": "O-002",
  "documents": [],
  "expect": {
    "active_trades": [
      "electrical",
      "plumbing"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "electrical",
      "plumbing"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "proclitic",
  "rationale": "Both trade terms are carried by attached prepositional proclitics and both are requested, so both are included and active. Requesting a separate price is not a split across lifecycle stages.",
  "spec_refs": [
    "2.2",
    "2.4"
  ],
  "text_ar": "للفيلا نحتاج أعمال السباكة، وللكهرباء سعر منفصل.",
  "text_en": "For the villa we need the plumbing works, and for the electrical works a separate price."
}'),
    ('{
  "adversarial": false,
  "bucket": "arabic_morphology",
  "case_key": "O-003",
  "documents": [],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "hvac"
      },
      {
        "component": "supply",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "plural",
  "rationale": "A broken plural of the equipment term identifies the HVAC trade, and the text addresses two lifecycle stages explicitly. Both stated components carry the trade disposition.",
  "spec_refs": [
    "2.1",
    "2.4"
  ],
  "text_ar": "نرجو تسعير توريد وتركيب المكيفات للشقق الثلاث.",
  "text_en": "Kindly price the supply and installation of the air conditioners for the three apartments."
}'),
    ('{
  "adversarial": false,
  "bucket": "arabic_morphology",
  "case_key": "O-004",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "excluded",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [
      "electrical"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "excluded"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "dual",
  "rationale": "The dual form is a morphological variant of the building noun and does not affect the trade reading, which is a removal with no other party identified. No trade is active.",
  "spec_refs": [
    "2.3",
    "2.9"
  ],
  "text_ar": "أعمال الكهرباء للمبنيين مستثناة من نطاقنا.",
  "text_en": "The electrical works for both buildings are excluded from our scope."
}'),
    ('{
  "adversarial": false,
  "bucket": "arabic_morphology",
  "case_key": "O-005",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "maintenance",
        "disposition": "existing_only",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "existing_only"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "ta_marbuta",
  "rationale": "An existing installation with a maintenance obligation is existing_only and contributes, and the ha spelling of ta marbuta is a realistic variant that changes nothing. The text addresses the maintenance stage only.",
  "spec_refs": [
    "2.3",
    "2.4"
  ],
  "text_ar": "مطلوب صيانه نظام إنذار الحريق القائم لمدة سنه واحده.",
  "text_en": "Maintenance of the existing fire alarm system is required for one year."
}'),
    ('{
  "adversarial": false,
  "bucket": "arabic_morphology",
  "case_key": "O-006",
  "documents": [],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "hamza",
  "rationale": "The hamza is dropped from both the leading noun and the trade term, which is a common tender spelling and leaves the trade reading intact. Fire is named and included.",
  "spec_refs": [
    "2.1",
    "2.2"
  ],
  "text_ar": "اعمال الاطفاء لمظلة المطبخ ضمن نطاقنا.",
  "text_en": "The fire extinguishing works for the kitchen hood are in our scope."
}'),
    ('{
  "adversarial": false,
  "bucket": "arabic_morphology",
  "case_key": "O-007",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [
      "elv"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "by_others"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "alef_maqsura",
  "rationale": "An identified other contractor makes the disposition by_others rather than excluded, and the yaa spelling of the final alef maqsura does not affect it. The trade is detected but does not activate.",
  "spec_refs": [
    "2.3",
    "2.8"
  ],
  "text_ar": "أعمال التيار الخفيف للمبني مع مقاول آخر.",
  "text_en": "The ELV works for the building are with another contractor."
}'),
    ('{
  "adversarial": true,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-001",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An umbrella services abbreviation used inside an organisation name describes the party, not a scope, so it activates nothing and detects nothing. The message is an administrative instruction rather than a scope enquiry, so no clarification is required.",
  "spec_refs": [
    "2.7",
    "2.8"
  ],
  "text_ar": "نرجو إصدار أمر الشراء باسم شركة الخليج إم إي بي للمقاولات ذ.م.م، وهو اسمنا التجاري المسجل.",
  "text_en": "Kindly address the purchase order to Gulf MEP Contracting LLC, which is our registered trade name."
}'),
    ('{
  "adversarial": true,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-002",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "An engineering discipline name used to describe a staff role is not evidence of a scope of works, so no trade is detected. The message is not a scope enquiry, so clarification is not required.",
  "spec_refs": [
    "2.7",
    "2.8"
  ],
  "text_ar": "نقوم بتوظيف مهندس كهرباء لقسم التسعير لدينا، ونرجو مشاركة أي سير ذاتية متاحة.",
  "text_en": "We are recruiting an electrical engineer for our estimation department; please share any CVs you may have."
}'),
    ('{
  "adversarial": true,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-003",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": true,
  "morphology_variant": null,
  "rationale": "The short form here carries its non-trade financial sense, which the surrounding text disambiguates completely, so it confirms no trade and nothing is detected. A payment instruction is not a scope enquiry.",
  "spec_refs": [
    "2.3",
    "2.7"
  ],
  "text_ar": "نرجو تحويل مبلغ الاحتجاز إلى حسابنا (A/C) المنتهي بـ 4471 وإرسال إشعار التحويل.",
  "text_en": "Please transfer the retention amount to our A/C number ending 4471 and send us the transfer advice."
}'),
    ('{
  "adversarial": true,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-004",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The umbrella abbreviation occurs only as a substring of a longer supplier name and therefore belongs to that name with no independent force. Nothing is detected and the message is not a scope enquiry.",
  "spec_refs": [
    "2.3",
    "2.8"
  ],
  "text_ar": "يجب صرف الدفعة لشركة MEPCO للتجارة، وهي مورّد المواد لدينا في هذا المشروع.",
  "text_en": "The payment should be released to MEPCO Trading, which is our material supplier for this project."
}'),
    ('{
  "adversarial": true,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-005",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A completeness modifier attached to a document set rather than to a trade or umbrella services term carries no trade meaning and must not activate anything. This holds in both languages independently.",
  "spec_refs": [
    "2.3",
    "2.6"
  ],
  "text_ar": "نرجو إرسال المجموعة الكاملة من الكتالوجات ومستندات اعتماد المواد لسجلاتنا.",
  "text_en": "Kindly send the complete set of catalogues and material submittals for our records."
}'),
    ('{
  "adversarial": true,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-006",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A grouping noun applied to documents is not an umbrella services term and gives no trade evidence, so nothing is detected. The message is logistical rather than a scope enquiry.",
  "spec_refs": [
    "2.3",
    "2.7"
  ],
  "text_ar": "سيتم إرسال حزمة المستندات إلى مكتبكم صباح الغد بالبريد السريع.",
  "text_en": "The documents package will be couriered to your office tomorrow morning."
}'),
    ('{
  "adversarial": false,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-007",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "ambiguous_trade",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "unknown",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [
      "fire"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "unknown"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": true,
  "morphology_variant": null,
  "rationale": "The short form is ambiguous between a trade sense and a commercial sense and the surrounding text does not disambiguate it, so it cannot confirm the trade and the disposition is unknown. Clarification is required with reason ambiguous_trade.",
  "spec_refs": [
    "2.3",
    "2.7"
  ],
  "text_ar": "نرجو تأكيد وضع الـ FA لهذا المشروع قبل اجتماع الغد.",
  "text_en": "Kindly confirm the FA position for this project before tomorrow''s meeting."
}'),
    ('{
  "adversarial": false,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-008",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "ambiguous_trade",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "unknown",
        "trade": "electrical"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "unknown",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "electrical",
      "hvac"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "unknown",
      "hvac": "unknown"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": true,
  "morphology_variant": null,
  "rationale": "The short form is ambiguous between two trades and the surrounding text does not resolve which is meant, so neither trade is confirmed and both candidates carry unknown. Neither activates and clarification is required.",
  "spec_refs": [
    "2.3",
    "2.7"
  ],
  "text_ar": "نرجو إفادتنا بسعركم للوحات الـ AC في الطابق الثاني.",
  "text_en": "Please advise your rate for the AC panels on the second floor."
}'),
    ('{
  "adversarial": true,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-009",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "by_others",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical"
    ],
    "trade_dispositions": {
      "elv": "by_others"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": true,
  "morphology_variant": null,
  "rationale": "An identified other contractor holds the named trade, which is by_others and does not activate. The shorter abbreviation appears only as a substring of the longer trade abbreviation and therefore has no independent force.",
  "spec_refs": [
    "2.3",
    "2.8"
  ],
  "text_ar": "سيقوم مقاول الـ ELV بسحب كابلاته بنفسه، ولا يُطلب منا شيء إضافي في تلك الحزمة.",
  "text_en": "The ELV contractor will pull his own cables; nothing further is required from us on that package."
}'),
    ('{
  "adversarial": true,
  "bucket": "ambiguous_non_trade",
  "case_key": "P-010",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "no_trade_detected",
    "clarification_required": true,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The completeness modifier attaches to a generic works noun rather than to a trade or umbrella services term, so it carries no trade meaning and nothing is detected. The message is nevertheless a genuine scope enquiry, so clarification is required with reason no_trade_detected.",
  "spec_refs": [
    "2.3",
    "2.7"
  ],
  "text_ar": "هل تتولون الأعمال الكاملة لمشروع من هذا النوع أم جزءًا منها فقط؟",
  "text_en": "Do you take on the full works for a project of this type, or only part of them?"
}'),
    ('{
  "adversarial": true,
  "bucket": "document_proposed",
  "case_key": "Q-001",
  "documents": [
    {
      "filename": "boq_extract_mechanical.pdf",
      "text_ar": "مستخلص من جدول الكميات: وحدات مناولة الهواء وشبكة مياه التبريد ومجاري الهواء والمخارج للطوابق من الأول إلى الثالث.",
      "text_en": "Bill of quantities extract: air handling units, chilled water pipework, ductwork and diffusers for levels 1 to 3."
    }
  ],
  "expect": {
    "active_trades": [],
    "clarification_reason": "unconfirmed_proposal",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "proposed",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "hvac"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [
      "hvac"
    ],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "plumbing"
    ],
    "trade_dispositions": {
      "hvac": "proposed"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The only evidence for the trade is an attached document, so the disposition is proposed and never included, and it always carries clarification. Attachments never activate, so no trade is active.",
  "spec_refs": [
    "2.8",
    "2.9"
  ],
  "text_ar": "نرجو مراجعة المرفق وإفادتنا بموقفكم.",
  "text_en": "Kindly review the attached and let us know your position."
}'),
    ('{
  "adversarial": false,
  "bucket": "document_proposed",
  "case_key": "Q-002",
  "documents": [
    {
      "filename": "single_line_diagram_rev_b.pdf",
      "text_ar": "مخطط الخط الأحادي، المراجعة ب: اللوحة الرئيسية واللوحات الفرعية وجداول الدوائر النهائية.",
      "text_en": "Single line diagram, revision B: main distribution board, sub main distribution boards and final circuit schedules."
    }
  ],
  "expect": {
    "active_trades": [],
    "clarification_reason": "unconfirmed_proposal",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "proposed",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [
      "electrical"
    ],
    "must_not_detect": [
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "electrical": "proposed"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": "alef_maqsura",
  "rationale": "Attachment evidence alone yields proposed for the trade it evidences, which does not contribute and requires clarification. The covering text names no trade at all.",
  "spec_refs": [
    "2.2",
    "2.8"
  ],
  "text_ar": "نرجو الاطلاع علي المرفق والإفادة.",
  "text_en": "Please see the attached and advise."
}'),
    ('{
  "adversarial": false,
  "bucket": "document_proposed",
  "case_key": "Q-003",
  "documents": [
    {
      "filename": "sprinkler_layout_level_2.pdf",
      "text_ar": "مخطط توزيع الرشاشات للطابق الثاني موضحًا مسارات الأنابيب والرؤوس ومجموعة صمام التحكم بالمنطقة.",
      "text_en": "Sprinkler layout for level 2 showing pipe routes, heads and the zone control valve assembly."
    }
  ],
  "expect": {
    "active_trades": [
      "hvac"
    ],
    "clarification_reason": "unconfirmed_proposal",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "proposed",
        "trade": "fire"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "hvac"
      }
    ],
    "detected_trades": [
      "fire",
      "hvac"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [
      "fire"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "proposed",
      "hvac": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "HVAC has text evidence and is included, while the second trade appears only in the attachment and is therefore proposed. The proposed disposition drives clarification with reason unconfirmed_proposal.",
  "spec_refs": [
    "2.7",
    "2.8"
  ],
  "text_ar": "نؤكد أن أعمال التكييف لدينا. وطقم المخططات المرفق مُرسل للاطلاع.",
  "text_en": "We confirm the HVAC works are with us. The attached drawing set is shared for information."
}'),
    ('{
  "adversarial": false,
  "bucket": "document_proposed",
  "case_key": "Q-004",
  "documents": [
    {
      "filename": "method_statement_fire.pdf",
      "text_ar": "بيان طريقة يشمل اختبارات واعتماد شبكة الرشاشات من طرف ثالث قبل تفتيش الجهة المختصة.",
      "text_en": "Method statement including third-party testing and certification of the sprinkler network prior to the authority inspection."
    }
  ],
  "expect": {
    "active_trades": [
      "fire"
    ],
    "clarification_reason": "unconfirmed_proposal",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "installation",
        "disposition": "included",
        "trade": "fire"
      },
      {
        "component": "testing",
        "disposition": "proposed",
        "trade": "fire"
      }
    ],
    "detected_trades": [
      "fire"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "fire": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The trade is named in the text and included, while a stage that appears only in the attachment and is unconfirmed is proposed at component level. A clarifying component disposition demands clarification even though the trade is active and clean.",
  "spec_refs": [
    "2.4",
    "2.7",
    "2.8"
  ],
  "text_ar": "أعمال مكافحة الحريق ضمن نطاقنا. ويشمل بيان الطريقة المرفق أيضًا اختبارات الطرف الثالث التي لم تُؤكد معنا.",
  "text_en": "The fire fighting works are in our scope. The attached method statement also covers third-party testing, which has not been confirmed with us."
}'),
    ('{
  "adversarial": true,
  "bucket": "document_proposed",
  "case_key": "Q-005",
  "documents": [
    {
      "filename": "device_schedule_security.xlsx",
      "text_ar": "جدول الأجهزة: كاميرات ومسجلات فيديو شبكية وقارئات التحكم بالدخول ووحدات تحكم الأبواب لكل طابق.",
      "text_en": "Device schedule: cameras, network video recorders, access control readers and door controllers by floor."
    }
  ],
  "expect": {
    "active_trades": [],
    "clarification_reason": "unconfirmed_proposal",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "proposed",
        "trade": "elv"
      }
    ],
    "detected_trades": [
      "elv"
    ],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [
      "elv"
    ],
    "must_not_detect": [
      "electrical",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {
      "elv": "proposed"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The trade is evidenced only by the attachment, so it is proposed and does not activate, and clarification is always carried. No other trade has evidence in either the text or the attachment.",
  "spec_refs": [
    "2.8",
    "2.9"
  ],
  "text_ar": "مرفق الملف الذي استلمناه من الاستشاري. نرجو الإفادة.",
  "text_en": "Attached is the pack we received from the consultant. Kindly advise."
}'),
    ('{
  "adversarial": false,
  "bucket": "document_proposed",
  "case_key": "Q-006",
  "documents": [
    {
      "filename": "data_outlet_schedule.xlsx",
      "text_ar": "جدول مخارج البيانات والخزائن يوضح المخارج لكل غرفة ولوحات التوصيل وغرفتي الاتصالات.",
      "text_en": "Data outlet and rack schedule listing outlets per room, patch panels and the two communication rooms."
    }
  ],
  "expect": {
    "active_trades": [
      "plumbing"
    ],
    "clarification_reason": "unconfirmed_proposal",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "complete_trade_scope",
        "disposition": "proposed",
        "trade": "elv"
      },
      {
        "component": "complete_trade_scope",
        "disposition": "included",
        "trade": "plumbing"
      }
    ],
    "detected_trades": [
      "elv",
      "plumbing"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [
      "elv"
    ],
    "must_not_detect": [],
    "trade_dispositions": {
      "elv": "proposed",
      "plumbing": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Text evidence yields a contributing disposition for the named trade, while the attachment-only trade is proposed. The proposed trade is detected but never activated by an attachment.",
  "spec_refs": [
    "2.8"
  ],
  "text_ar": "أعمال السباكة مؤكدة معنا؛ والجدول المرفق مُرسل للاطلاع فقط.",
  "text_en": "Plumbing is confirmed with us; the attached schedule is sent for your information only."
}'),
    ('{
  "adversarial": false,
  "bucket": "document_proposed",
  "case_key": "Q-007",
  "documents": [
    {
      "filename": "consultant_note_electrical.pdf",
      "text_ar": "مذكرة الاستشاري تُدرج التصميم التفصيلي لمخططات توزيع القدرة ضمن الحزمة.",
      "text_en": "Consultant note listing detailed design of the low current and power distribution layouts as part of the package."
    }
  ],
  "expect": {
    "active_trades": [
      "electrical"
    ],
    "clarification_reason": "unconfirmed_proposal",
    "clarification_required": true,
    "component_dispositions": [
      {
        "component": "design",
        "disposition": "proposed",
        "trade": "electrical"
      },
      {
        "component": "installation",
        "disposition": "included",
        "trade": "electrical"
      }
    ],
    "detected_trades": [
      "electrical"
    ],
    "dispatch_blockers": [
      "clarification_pending"
    ],
    "must_not_activate": [],
    "must_not_detect": [],
    "trade_dispositions": {
      "electrical": "included"
    }
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A stage inferred from an attachment and not confirmed by the customer is proposed at component level, while the trade itself has text evidence and stays active. The unresolved proposal changes the quoted component scope.",
  "spec_refs": [
    "2.4",
    "2.8",
    "2.9"
  ],
  "text_ar": "التركيبات الكهربائية لدينا. كما تُدرج مذكرة الاستشاري المرفقة التصميم التفصيلي الذي لم يُطلب منا تسعيره.",
  "text_en": "The electrical installation is with us. The attached consultant note also lists the detailed design, which we have not been asked to price."
}'),
    ('{
  "adversarial": true,
  "bucket": "no_detection",
  "case_key": "R-001",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The message concerns vendor registration documents and gives no evidence of any trade, so nothing is detected and no trade is active. It is not a scope enquiry, so clarification is not required.",
  "spec_refs": [
    "2.7",
    "2.9"
  ],
  "text_ar": "نرجو تزويدنا بالرخصة التجارية وشهادة ضريبة القيمة المضافة لاستكمال تسجيلكم كمورّد.",
  "text_en": "Kindly share your trade licence and VAT certificate so we can complete your vendor registration."
}'),
    ('{
  "adversarial": true,
  "bucket": "no_detection",
  "case_key": "R-002",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A commercial terms question carries no trade evidence and is not a scope enquiry, so nothing is detected and clarification is false. The no_active_trade blocker is still raised.",
  "spec_refs": [
    "2.7",
    "2.9"
  ],
  "text_ar": "ما هي شروط الدفع المعتمدة لديكم وما نسبة الاحتجاز التي تطبقونها؟",
  "text_en": "What are your standard payment terms and what retention percentage do you apply?"
}'),
    ('{
  "adversarial": true,
  "bucket": "no_detection",
  "case_key": "R-003",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A question about geographic coverage is not a statement or enquiry about a scope of works, so no trade is detected and clarification is not required. The only blocker is the absence of an active trade.",
  "spec_refs": [
    "2.7",
    "2.9"
  ],
  "text_ar": "هل تعملون في رأس الخيمة أم تغطون دبي والشارقة فقط؟",
  "text_en": "Do you work in Ras Al Khaimah, or do you cover Dubai and Sharjah only?"
}'),
    ('{
  "adversarial": false,
  "bucket": "no_detection",
  "case_key": "R-004",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": "no_trade_detected",
    "clarification_required": true,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "clarification_pending",
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "The message is a genuine scope enquiry but names no trade and gives no other trade evidence, so nothing is detected. Clarification is required with reason no_trade_detected.",
  "spec_refs": [
    "2.7",
    "2.9"
  ],
  "text_ar": "نقوم بإعداد قائمة مختصرة بمقاولي الباطن لمشروع جديد. نرجو تأكيد ما يمكنكم تغطيته لنا.",
  "text_en": "We are shortlisting subcontractors for a new project. Please confirm what you would be able to cover for us."
}'),
    ('{
  "adversarial": true,
  "bucket": "no_detection",
  "case_key": "R-005",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "Scheduling a site visit is not a scope statement or a scope enquiry and gives no trade evidence. Nothing is detected and clarification is false.",
  "spec_refs": [
    "2.7",
    "2.9"
  ],
  "text_ar": "متى يمكن لفريقكم زيارة الموقع؟ نحن متاحون صباح يوم الثلاثاء.",
  "text_en": "When can your team visit the site? We are available on Tuesday morning."
}'),
    ('{
  "adversarial": true,
  "bucket": "no_detection",
  "case_key": "R-006",
  "documents": [],
  "expect": {
    "active_trades": [],
    "clarification_reason": null,
    "clarification_required": false,
    "component_dispositions": [],
    "detected_trades": [],
    "dispatch_blockers": [
      "no_active_trade"
    ],
    "must_not_activate": [],
    "must_not_detect": [
      "electrical",
      "elv",
      "fire",
      "hvac",
      "plumbing"
    ],
    "trade_dispositions": {}
  },
  "gulf_phrasing": false,
  "mixed_language": false,
  "morphology_variant": null,
  "rationale": "A correspondence acknowledgement carries no trade evidence and is not a scope enquiry, so nothing is detected and no clarification is required. The absence of an active trade is the only blocker.",
  "spec_refs": [
    "2.7",
    "2.9"
  ],
  "text_ar": "نرجو تأكيد استلام بريدنا السابق والرد في الوقت المناسب لكم.",
  "text_en": "Please confirm receipt of our earlier email and revert at your convenience."
}')
  ) v(t), lateral (select v.t::jsonb) z(j);

  get diagnostics v_n = row_count;
  if v_n <> 131 then
    raise exception 'HOLDOUT V2 LOAD: inserted % case rows, expected 131', v_n;
  end if;

  ------------------------------------------------------ 3. immutable protections
  create function holdout_v2.trg_immutable() returns trigger
    language plpgsql as $IMM$
  begin
    raise exception 'holdout v2 %.% is immutable: % refused. Sealed expectations change only through the P2-C5 expectation-change controls.',
      tg_table_schema, tg_table_name, tg_op;
    return null;
  end $IMM$;

  create function holdout_v2.trg_seal_guard() returns trigger
    language plpgsql as $SEAL$
  begin
    if tg_op = 'DELETE' then
      raise exception 'holdout v2 seal is immutable: DELETE refused.';
    end if;
    if new.holdout_version is distinct from old.holdout_version
       or new.checksum_sha256 is distinct from old.checksum_sha256
       or new.case_count      is distinct from old.case_count
       or new.seal_document   is distinct from old.seal_document
       or new.loaded_by       is distinct from old.loaded_by then
      raise exception 'holdout v2 seal is immutable: sealed columns may not be updated.';
    end if;
    if old.checksum_verified is not null then
      raise exception 'holdout v2 seal verification is write-once and has already been recorded.';
    end if;
    return new;
  end $SEAL$;

  create trigger case_v2_immutable       before update or delete on holdout_v2.case_v2
    for each row execute function holdout_v2.trg_immutable();
  create trigger case_v2_immutable_trunc before truncate on holdout_v2.case_v2
    for each statement execute function holdout_v2.trg_immutable();
  create trigger seal_guard              before update or delete on holdout_v2.seal
    for each row execute function holdout_v2.trg_seal_guard();
  create trigger seal_immutable_trunc    before truncate on holdout_v2.seal
    for each statement execute function holdout_v2.trg_immutable();
  create trigger ror_immutable           before update or delete on holdout_v2.result_of_record
    for each row execute function holdout_v2.trg_immutable();
  create trigger ri_immutable            before update or delete on holdout_v2.result_interpretation
    for each row execute function holdout_v2.trg_immutable();
  create trigger rcv_immutable           before update or delete on holdout_v2.result_case_verdict
    for each row execute function holdout_v2.trg_immutable();

  ------------------------------------------------------ 4. seal
  insert into holdout_v2.seal
    (id,holdout_version,checksum_sha256,case_count,seal_document,bundle_manifest_sha,loaded_by)
  values (1, 'v2', c_expected, 131, '{
  "authored_from": "P2C1_HOLDOUT_V2_AUTHORING_BRIEF_SANITIZED.md",
  "brief_sha256": "94cfadfee27f5803580ad5783c0748fa96b160bd7e200057be1dc2894d202fec",
  "canonicaliser": "validate_holdout_v2.mjs",
  "case_count": 131,
  "checksum_sha256": "44973f9169510a06468a20eb2ba068f932e25bdd9ad7e0d85d4479b5e03d4801",
  "holdout_version": "v2",
  "immutability": "Expected outcomes are frozen. They may be changed only through the approved expectation-change controls, which require a stated reason, a work item and a named person.",
  "independence": {
    "read_database": false,
    "read_failure_reports": false,
    "read_prior_holdout": false,
    "read_repository": false,
    "statement": "This session read only the sanitized authoring brief."
  },
  "sealed_at": "2026-08-02T20:12:02Z",
  "sealed_by": "cowork-independent-authoring-session-2026-08-02"
}
'::jsonb, '4d0aa22872c750d6a0e34664ab668018cb7c208f6da97fbca179e2901ed5d61d',
          'cowork-independent-evaluation-session-2026-08-02');

  ------------------------------------------------------ 5. recompute checksum FROM THE LOADED ROWS
  select string_agg('    ' || replace(case_json, chr(10), chr(10) || '    '),
                    ',' || chr(10) order by case_key collate "C")
    into v_parts from holdout_v2.case_v2;

  v_doc := '{' || chr(10)
        || '  "cases": [' || chr(10)
        || v_parts || chr(10)
        || '  ],' || chr(10)
        || '  "holdout_version": "v2"' || chr(10)
        || '}' || chr(10);

  v_sum := encode(extensions.digest(convert_to(v_doc, 'UTF8'), 'sha256'), 'hex');

  ------------------------------------------------------ 6 and 7. verify or refuse
  if v_sum <> c_expected then
    raise exception 'HOLDOUT V2 SEAL MISMATCH - refusing to load or evaluate. recomputed=% expected=%', v_sum, c_expected;
  end if;

  update holdout_v2.seal set loaded_checksum = v_sum, checksum_verified = true where id = 1;

  raise notice 'HOLDOUT V2 LOADED AND SEALED: 131 cases, checksum %', v_sum;
end
$HOLDOUT_V2_LOAD$;
