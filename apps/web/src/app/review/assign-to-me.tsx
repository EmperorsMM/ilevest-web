"use client";
// Intake action: Ops assigns the check to themselves (the launch human holds
// field_agent, so the worker-role requirement is satisfied). The database is
// the gate; its refusals are shown verbatim.
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "../../lib/supabase/client";

export default function AssignToMe({ checkId }: { checkId: string }) {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const assign = async () => {
    setBusy(true); setErr(null);
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setErr("Not signed in."); setBusy(false); return; }
    const { error } = await supabase.rpc("assign_check", { p_check: checkId, p_worker: user.id });
    if (error) setErr(error.message);
    else router.refresh();
    setBusy(false);
  };

  return (
    <span>
      <button className="btn" style={{ padding: "2px 10px", fontSize: 13 }} disabled={busy} onClick={assign}>
        Assign to me
      </button>
      {err && <><br /><small className="auth-err">{err}</small></>}
    </span>
  );
}
