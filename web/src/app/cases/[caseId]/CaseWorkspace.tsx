"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/lib/supabase";

type CaseWorkspaceProps = {
  caseId: string;
};

type CaseRecord = {
  id: string;
  title: string;
  description: string | null;
  status: string;
  priority: string;
  source: string;
  case_type: string | null;
  initiated_by: string | null;
  customer_id: string | null;
  assigned_user_id: string | null;
  assigned_team_id: string | null;
  created_at: string;
};

type SessionState =
  | { status: "loading" }
  | { status: "locked" }
  | { status: "verification_required" }
  | { status: "error" }
  | {
      status: "acquired";
      token: string;
      expiresAt: string;
      record: CaseRecord;
    };

// Serialise case-opening lifecycles for the same case within this tab.
// A failed operation must not prevent subsequent operations.
const caseOpeningQueues = new Map<string, Promise<void>>();

function coordinateCaseOpening(
  caseId: string,
  operation: () => Promise<void>
): Promise<void> {
  const previous = caseOpeningQueues.get(caseId) ?? Promise.resolve();

  const current = previous
    .catch(() => undefined)
    .then(operation);

  const settled = current.then(
    () => undefined,
    () => undefined
  );

  caseOpeningQueues.set(caseId, settled);

  void settled.then(() => {
    if (caseOpeningQueues.get(caseId) === settled) {
      caseOpeningQueues.delete(caseId);
    }
  });

  return current;
}

export default function CaseWorkspace({
  caseId,
}: CaseWorkspaceProps) {
  const [session, setSession] = useState<SessionState>({
    status: "loading",
  });

  const leaveSessionRef = useRef<null | (() => Promise<boolean>)>(null);
  const leavingRef = useRef(false);
  const router = useRouter();
  const [leaveError, setLeaveError] = useState<string | null>(null);

  async function handleBack() {
    if (leavingRef.current) return;

    leavingRef.current = true;
    setLeaveError(null);

    try {
      const leave = leaveSessionRef.current;

      if (!leave || !(await leave())) {
        setLeaveError("Could not confirm the case was released. Please try again.");
        return;
      }

      router.push("/cases");
      router.refresh();
    } catch {
      setLeaveError("Unable to leave the case safely. Please try again.");
    } finally {
      leavingRef.current = false;
    }
  }

  useEffect(() => {
    let active = true;
    let lockToken: string | null = null;
    let openedRecord: CaseRecord | null = null;
    let renewalTimer: ReturnType<typeof setTimeout> | null = null;
    let expiryTimer: ReturnType<typeof setTimeout> | null = null;

    function scheduleExpiryCheck(expiresAt: string) {
      if (!active) return;

      if (expiryTimer) clearTimeout(expiryTimer);

      const delay = Math.max(
        0,
        Date.parse(expiresAt) - Date.now()
      );

      expiryTimer = setTimeout(() => {
        if (!active) return;

        setSession({ status: "verification_required" });

        if (renewalTimer) {
          clearTimeout(renewalTimer);
          renewalTimer = null;
        }
      }, delay);
    }

    function scheduleRenewal(
      token: string,
      expiresAt: string,
      retry = false
    ) {
      if (!active) return;

      if (renewalTimer) {
        clearTimeout(renewalTimer);
      }

      const renewalTime = Date.parse(expiresAt) - 60_000;
      const delay = retry
        ? 15_000
        : Math.max(0, renewalTime - Date.now());

      renewalTimer = setTimeout(async () => {
        renewalTimer = null;

        if (!active) return;

        const { data: newExpiry, error } = await supabase.rpc(
          "renew_case_lock",
          {
            p_case_id: caseId,
            p_lock_token: token,
          }
        );

        if (!active) return;

        if (error) {
          // A failed request does not release the database lock.
          // Retry only while the previous lease may still be valid.
          const remainingMs = Date.parse(expiresAt) - Date.now();

          if (remainingMs > 15_000) {
            scheduleRenewal(token, expiresAt, true);
          } else {
            setSession({ status: "verification_required" });
          }

          return;
        }

        if (
          !newExpiry ||
          !Number.isFinite(Date.parse(newExpiry)) ||
          Date.parse(newExpiry) <= Date.now() ||
          !openedRecord
        ) {
          setSession({ status: "verification_required" });
          return;
        }

        const confirmedRecord = openedRecord;

        setSession((current) =>
          current.status === "acquired" ||
          current.status === "verification_required"
            ? {
                status: "acquired",
                token,
                expiresAt: newExpiry,
                record: confirmedRecord,
              }
            : current
        );

        scheduleExpiryCheck(newExpiry);
        scheduleRenewal(token, newExpiry);
      }, delay);
    }

    async function releaseSession(token: string): Promise<boolean> {
      const { data, error } = await supabase.rpc(
        "close_case_session",
        {
          p_case_id: caseId,
          p_lock_token: token,
        }
      );

      if (error) {
        console.error("Case session release failed", error);
        return false;
      }

      return data === true;
    }

    async function openSession() {
      if (!active) return;

      const { data, error } = await supabase.rpc(
        "open_case_session",
        { p_case_id: caseId }
      );

      if (error) {
        if (active) setSession({ status: "error" });
        return;
      }

      const result = data?.[0];

      if (
        !result?.acquired ||
        !result.lock_token ||
        !result.lock_expires_at
      ) {
        if (active) setSession({ status: "locked" });
        return;
      }

      const acquiredToken: string = result.lock_token;
      lockToken = acquiredToken;

      if (!active) {
        lockToken = null;
        await releaseSession(acquiredToken);
        return;
      }

      const { data: caseData, error: detailsError } =
        await supabase.rpc("get_locked_case_details", {
          p_case_id: caseId,
          p_lock_token: acquiredToken,
        });

      if (!active) return;

      const record = caseData?.[0] as CaseRecord | undefined;

      if (detailsError || !record) {
        setSession({ status: "error" });
        lockToken = null;
        await releaseSession(acquiredToken);
        return;
      }

      openedRecord = record;

      setSession({
        status: "acquired",
        token: acquiredToken,
        expiresAt: result.lock_expires_at,
        record,
      });

      scheduleExpiryCheck(result.lock_expires_at);
      scheduleRenewal(
        acquiredToken,
        result.lock_expires_at
      );
    }

    let signalCleanup: () => void = () => {};
    const cleanupRequested = new Promise<void>((resolve) => {
      signalCleanup = resolve;
    });

    let releaseConfirmed = true;

    const lifecycle = coordinateCaseOpening(caseId, async () => {
      if (!active) return;

      try {
        await openSession();
        await cleanupRequested;
      } finally {
        if (lockToken) {
          const token = lockToken;
          lockToken = null;
          releaseConfirmed = await releaseSession(token);
        }
      }
    });

    const leave = async (): Promise<boolean> => {
      active = false;

      if (renewalTimer) {
        clearTimeout(renewalTimer);
        renewalTimer = null;
      }

      if (expiryTimer) {
        clearTimeout(expiryTimer);
        expiryTimer = null;
      }

      signalCleanup();

      try {
        await lifecycle;
        return releaseConfirmed;
      } catch {
        return false;
      }
    };

    leaveSessionRef.current = leave;

    return () => {
      if (leaveSessionRef.current === leave) {
        leaveSessionRef.current = null;
      }
      active = false;

      if (renewalTimer) {
        clearTimeout(renewalTimer);
        renewalTimer = null;
      }

      if (expiryTimer) {
        clearTimeout(expiryTimer);
        expiryTimer = null;
      }

      signalCleanup();
    };
  }, [caseId]);

  return (
    <main className="min-h-screen bg-[#FAF9F6] px-6 py-8 text-[#39352F]">
      <div className="mx-auto max-w-6xl">
        <button
          type="button"
          onClick={() => void handleBack()}
          className="text-sm text-[#51483F] hover:underline"
        >
          ← Back to cases
        </button>

        {leaveError && (
          <p role="alert" className="mt-3 text-sm text-red-700">
            {leaveError}
          </p>
        )}

        <h1 className="mt-6 text-2xl font-semibold">
          Case {caseId}
        </h1>

        <p className="mt-4 text-sm text-[#756B60]">
          {session.status === "loading"
            ? "Checking exclusive case access..."
            : session.status === "locked"
              ? "This case is currently locked by another employee."
              : session.status === "verification_required"
                ? "Exclusive access needs verification. Protected actions are unavailable until access is restored."
                : session.status === "error"
                  ? "Unable to open this case. Please return to the case queue."
                  : `Exclusive access granted: ${session.record.title}`}
        </p>
      </div>
    </main>
  );
}
