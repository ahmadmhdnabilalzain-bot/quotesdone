            excepted = !!ex && (ex as { allowed?: unknown }).allowed === true;
            if (!excepted) skipped.push({ route: m, reason: `exception: ${(ex as { rule?: string })?.rule ?? 'no answer'}` });
          } catch (_e) { excepted = false; }
        }
        if (!excepted) { skipped.push({ route: m, reason: `${gate.rule}: ${gate.reason}` }); continue; }
      }
      ladder.push(m);
    }
    // Every route on the ladder is open-circuit: fail CLOSED and say so, rather than retrying into
    // a wall and reporting it as a model failure.
    // A REVIEW WHOSE REVIEWER CANNOT BE CALLED IS HELD, NOT SKIPPED (#880 review, item 6). Every route open-circuit for a
    // reason other than the founder's hold (which holds everything, reviewed or not) is recorded as a review_hold.
    // A sandbox call whose rehearsal window closed is refused on EVERY model, reviewed or not: that is the test run's
    // own end, not a missing reviewer (18 Oct 2026: hold 71 reached the founder's digest this way).
    if (counterpart && !ladder.length && fullLadder.length && skipped.some((x) => !/^(founder_hold|exception|rehearsal_window_closed):/.test(x.reason))) {
      await rpcSafe('fn_review_hold_record', { p_task_class: route.task_class ?? null, p_fn: fnName, p_agent_key: body.agent ?? null,
        p_counterpart_model: counterpart, p_why: 'reviewer unreachable: ' + skipped.map((x) => x.route + ' (' + x.reason + ')').join('; ') });
    }
    if (!ladder.length && fullLadder.length) {
      // A HELD ROUTE IS STILL A ROUTING DECISION, AND THE ROUTER MUST SAY SO (3 Sep 2026). The
      // policy chose a model for this task class and the kernel gate refused every route on the
      // ladder; nothing was called and nothing was spent. Before this line, that decision left no
      // row at all: with the founder's hold open, ai_cost_log recorded zero routed requests for
      // nineteen days while callers reached this branch dozens of times a week, so the router
      // read as dead when it was refusing exactly as instructed. Logged the way the deterministic
      // refusal above is logged — model 'none', zero tokens, the rationale in words — so spend,
      // failure and confidence instruments see a policy answer, not a call, and the routing
      // rationale names the model it would have used and the rule that held it.
      await llmLog({
        p_fn: fnName, p_dept: body.dept ?? null, p_agent: body.agent ?? null,
        p_task_class: route.task_class ?? null, p_model: 'none',
        p_because: route.why + ' | HELD: routed to ' + model + ' by policy, no provider call was made — '
                   + skipped.map(s => s.route + ' (' + s.reason + ')').join('; '),
        p_tier: route.tier ?? null, p_prompt_tokens: 0, p_output_tokens: 0, p_cached: false,
        p_cache_key: null, p_latency_ms: Date.now() - t0, p_ok: true,
      });
      return J({ ok: false, used_llm: false, outcome: 'circuit_open',
        error: 'every model route for this task class is open-circuit',
        routes: skipped, task_class: route.task_class, cost_usd: 0 }, 503);
    }
    // attempt_no is assigned SERVER-SIDE by fn_record_llm_attempt and cannot be set by this caller.
