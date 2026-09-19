(() => {
  const pipelineStatuses = [
    "New Lead",
    "Not Contacted",
    "Call Attempted",
    "No Answer",
    "Call Back Requested",
    "Contacted",
    "Interview Scheduled",
    "Interview Taken",
    "Follow-Up After Interview",
    "Interested",
    "Not Interested",
    "Documents Requested",
    "Documents Pending",
    "Partial Documents Received",
    "Documents Received",
    "Documents Under Review",
    "Qualification Pending",
    "Qualified",
    "Not Qualified",
    "Manager Review Required",
    "Ready for Onboarding",
    "Onboarding Started",
    "Onboarding Documents Pending",
    "Ready to Start",
    "Active / Hired",
    "Unresponsive",
    "Future Follow-Up",
    "Duplicate",
    "Rejected",
    "Archived",
  ];
  const callResults = [
    "No Answer",
    "Voicemail Left",
    "Interested",
    "Not Interested",
    "Call Back Later",
    "Interview Completed",
    "Documents Requested",
    "Documents Received",
    "Wrong Number",
    "Qualified",
    "Not Qualified",
  ];
  const esc = (s) =>
    String(s ?? "").replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[c],
    );
  function sheet(title, body, onSave, saveLabel = "Save changes") {
    let el = document.querySelector("#crmActionSheet");
    if (el) el.remove();
    el = document.createElement("div");
    el.id = "crmActionSheet";
    el.className = "action-sheet open";
    el.innerHTML = `<div class="action-card"><div class="action-head"><h3>${esc(title)}</h3><button class="close" data-close>×</button></div><form><div class="action-body">${body}</div><div class="action-foot"><button type="button" class="secondary" data-close>Cancel</button><button class="primary" type="submit">${esc(saveLabel)}</button></div></form></div>`;
    document.body.append(el);
    el.querySelectorAll("[data-close]").forEach(
      (b) => (b.onclick = () => el.remove()),
    );
    el.onclick = (e) => {
      if (e.target === el) el.remove();
    };
    el.querySelector("form").onsubmit = async (e) => {
      e.preventDefault();
      const btn =
        e.submitter || e.currentTarget.querySelector('[type="submit"]');
      if (btn.disabled) return;
      btn.disabled = true;
      try {
        await onSave(Object.fromEntries(new FormData(e.currentTarget)));
        el.remove();
      } catch (err) {
        toast(err.message || "Unable to save.");
        btn.disabled = false;
      }
    };
  }
  async function recordHistory(leadId, field, oldValue, newValue) {
    const { error } = await sb.from("oo_status_history").insert({
      lead_id: Number(leadId),
      field_name: field,
      old_value: String(oldValue ?? ""),
      new_value: String(newValue ?? ""),
      changed_by: currentProfile.id,
    });
    if (error) toast("Change saved, but status history could not be recorded.");
    await logActivity(
      leadId,
      "Field Updated",
      `${field}: ${oldValue || "—"} → ${newValue || "—"}`,
    );
  }
  function editLead() {
    const l = currentLead;
    if (!l) return;
    sheet(
      `Edit ${l.name}`,
      `<div class="status-grid"><label class="field"><span>Full name</span><input name="name" required value="${esc(l.name)}"></label><label class="field"><span>Company</span><input name="company" value="${esc(l.company || "")}"></label><label class="field"><span>Phone</span><input name="phone" required value="${esc(l.phone)}"></label><label class="field"><span>Email</span><input name="email" type="email" value="${esc(l.email || "")}"></label><label class="field"><span>City</span><input name="city" value="${esc(l.city || "")}"></label><label class="field"><span>State</span><input name="state" maxlength="2" value="${esc(l.state || "")}"></label><label class="field"><span>Truck type</span><input name="truck" value="${esc(l.truck || "")}"></label><label class="field"><span>Applied under authority</span><input name="authorityCompany" value="${esc(l.authorityCompany || "")}"></label><label class="field full"><span>Recruiter notes</span><textarea name="notes">${esc(l.notes || "")}</textarea></label></div>`,
      async (d) => {
        const before = { ...l };
        await LeadRepository.update(sb, l.id, LeadRepository.editableFields(d));
        Object.assign(l, d);
        for (const k of Object.keys(d))
          if (String(before[k] ?? "") !== String(d[k] ?? ""))
            await recordHistory(l.id, k, before[k], d[k]);
        render();
        openLead(l.id);
        toast("Lead updated.");
      },
    );
  }
  function changeStatus() {
    const l = currentLead;
    if (!l) return;
    sheet(
      "Change recruiting status",
      `<div class="status-grid"><label class="field"><span>Pipeline status</span><select name="pipeline">${pipelineStatuses.map((s) => `<option ${s === (l.pipelineStatus || l.status) ? "selected" : ""}>${s}</option>`).join("")}</select></label><label class="field"><span>Call result</span><select name="callResult"><option value="">Select result</option>${callResults.map((s) => `<option ${s === l.lastCallResult ? "selected" : ""}>${s}</option>`).join("")}</select></label><label class="field full"><span>Call notes</span><textarea name="notes" placeholder="Add the important outcome and next action"></textarea></label></div>`,
      async (d) => {
        const old = l.pipelineStatus || l.status;
        const { error } = await sb
          .from("oo_leads")
          .update({
            pipeline_status: d.pipeline,
            last_call_result: d.callResult || null,
            last_contact_at: new Date().toISOString(),
          })
          .eq("id", Number(l.id));
        if (error) throw error;
        l.pipelineStatus = d.pipeline;
        l.status = d.pipeline;
        l.lastCallResult = d.callResult;
        if (d.callResult) {
          const { error: callError } = await sb.from("oo_call_logs").insert({
            lead_id: Number(l.id),
            user_id: currentProfile.id,
            result: d.callResult,
            notes: d.notes || null,
          });
          if (callError)
            toast("Status saved, but the call log could not be saved.");
        }
        await recordHistory(l.id, "pipeline_status", old, d.pipeline);
        render();
        openLead(l.id);
        toast("Status and call result saved.");
      },
    );
  }
  function scheduleFollowup() {
    const l = currentLead;
    if (!l) return;
    sheet(
      "Schedule follow-up",
      `<div class="status-grid"><label class="field"><span>Date and time</span><input name="at" type="datetime-local" required></label><label class="field"><span>Priority</span><select name="priority"><option>High</option><option selected>Medium</option><option>Low</option></select></label><label class="field"><span>Reason</span><select name="reason"><option>Call</option><option>Interview</option><option>Documents</option><option>Qualification review</option></select></label><label class="field full"><span>Notes</span><textarea name="notes"></textarea></label></div>`,
      async (d) => {
        const iso = new Date(d.at).toISOString();
        const { error } = await sb.from("oo_followups").insert({
          lead_id: Number(l.id),
          recruiter_id: l.recruiterId || currentProfile.id,
          follow_up_at: iso,
          follow_up_type: d.reason,
          status: "Scheduled",
          notes: `[${d.priority}] ${d.notes || ""}`.trim(),
        });
        if (error) throw error;
        const { error: leadError } = await sb
          .from("oo_leads")
          .update({ next_follow_up_at: iso })
          .eq("id", Number(l.id));
        if (leadError) {
          toast(
            "Follow-up created, but the lead summary could not be updated.",
          );
          return;
        }
        await logActivity(
          l.id,
          "Follow-Up Scheduled",
          `${d.reason} scheduled for ${new Date(iso).toLocaleString()}.`,
        );
        toast("Follow-up scheduled.");
        await loadPortal();
        openLead(l.id);
      },
    );
  }
  async function archiveLead() {
    const l = currentLead;
    if (!l) return;
    const restore = Boolean(l.archivedAt);
    if (
      !restore &&
      !confirm(`Archive ${l.name}? The record and history will be preserved.`)
    )
      return;
    const value = restore ? null : new Date().toISOString();
    const { error } = await sb
      .from("oo_leads")
      .update({
        archived_at: value,
        archived_by: restore ? null : currentProfile.id,
        pipeline_status: restore ? "New Lead" : "Archived",
      })
      .eq("id", Number(l.id));
    if (error) return toast(error.message);
    await logActivity(
      l.id,
      restore ? "Lead Restored" : "Lead Archived",
      `${l.name} was ${restore ? "restored" : "archived"}.`,
    );
    document.querySelector("#drawer").classList.remove("open");
    await loadPortal();
    toast(
      restore
        ? "Lead restored."
        : "Lead archived. Undo is available from archived records.",
    );
  }
  function installActions() {
    const top = document.querySelector("#drawer .drawer-top");
    if (!top || document.querySelector(".lead-actions")) return;
    const bar = document.createElement("div");
    bar.className = "lead-actions";
    bar.innerHTML =
      '<button class="primary" data-act="edit">Edit Lead</button><button class="secondary" data-act="status">Change Status</button><button class="secondary" data-act="follow">Schedule Follow-Up</button><button class="secondary" data-act="note">Add Note</button><button class="secondary danger" data-act="archive">Archive</button>';
    top.after(bar);
    bar.onclick = (e) => {
      const a = e.target.closest("[data-act]")?.dataset.act;
      if (a === "edit") editLead();
      if (a === "status") changeStatus();
      if (a === "follow") scheduleFollowup();
      if (a === "note") {
        document.querySelector('[data-tab="notes"]')?.click();
      }
      if (a === "archive") archiveLead();
    };
  }
  function onLeadOpened() {
    document.querySelector("[data-permanent-delete]")?.remove();
    installActions();
    const l = currentLead;
    const b = document.querySelector('[data-act="archive"]');
    if (b) {
      b.textContent = l?.archivedAt ? "Restore" : "Archive";
      b.classList.toggle("danger", !l?.archivedAt);
    }
  }
  function improveFilters() {
    const filters = document.querySelector("#leads .filters");
    if (!filters || document.querySelector("#truckFilter")) return;
    const truck = document.createElement("select");
    truck.id = "truckFilter";
    truck.setAttribute("aria-label", "Truck type");
    truck.innerHTML =
      '<option value="">All truck types</option>' +
      [...new Set(leads.map((l) => l.truck).filter(Boolean))]
        .map((x) => `<option>${esc(x)}</option>`)
        .join("");
    const state = document.createElement("select");
    state.id = "stateFilter";
    state.setAttribute("aria-label", "State");
    state.innerHTML =
      '<option value="">All states</option>' +
      [...new Set(leads.map((l) => l.state).filter(Boolean))]
        .sort()
        .map((x) => `<option>${esc(x)}</option>`)
        .join("");
    filters.append(truck, state);
    const archive = document.createElement("label");
    archive.className = "archive-toggle";
    archive.innerHTML =
      '<input id="archiveFilter" type="checkbox"> Archived leads';
    archive.querySelector("input").onchange = render;
    filters.append(archive);
    [truck, state].forEach((x) => (x.onchange = render));
  }
  function initialize() {
    if (!document.body.classList.contains("authenticated")) return;
    leads.forEach((l) => {
      l.pipelineStatus = l.pipeline_status || l.pipelineStatus || l.status;
      l.lastCallResult = l.last_call_result || l.lastCallResult;
      l.archivedAt = l.archived_at || l.archivedAt;
    });

    improveFilters();
  }
  window.CrmRecruiting = { initialize, onLeadOpened };
})();
