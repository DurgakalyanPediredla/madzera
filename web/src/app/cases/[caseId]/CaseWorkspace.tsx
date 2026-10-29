"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/lib/supabase";
import {
  getCaseEvidence,
  downloadCaseEvidence,
  listEmployeeCaseEvidenceUploadReservations,
  type CaseEvidenceAttachment,
} from "@/lib/caseEvidence";
import CaseActivityEditor from "./CaseActivityEditor";
import {
  readSavedCaseSession,
  saveCaseSession,
  clearSavedCaseSession,
} from "./caseSessionRecovery";

type CaseWorkspaceProps = {
  caseId: string;
};

type CaseRecord = {
  id: string;
  case_reference: string;
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

type CaseActivityComment = {
  id: string;
  body: string;
  created_at: string;
  author_user_id: string | null;
  author_name: string;
};

type CaseAuditEvent = {
  id: string;
  event_type: string;
  created_at: string;
  actor_user_id: string | null;
  actor_name: string;
  from_status: string | null;
  to_status: string | null;
  from_team_name: string | null;
  to_team_name: string | null;
  from_user_name: string | null;
  to_user_name: string | null;
  details: string | null;
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
  const [showLoadingSkeleton, setShowLoadingSkeleton] = useState(false);
  const [customerReference, setCustomerReference] = useState<{
    caseId: string;
    customerId: string;
    reference: string;
  } | null>(null);
  const [customerReferenceError, setCustomerReferenceError] = useState<{
    caseId: string;
    customerId: string;
  } | null>(null);

  useEffect(() => {
    if (session.status !== "loading") {
      return;
    }

    const timer = window.setTimeout(() => {
      setShowLoadingSkeleton(true);
    }, 180);

    return () => window.clearTimeout(timer);
  }, [session.status]);

  const activeCustomerId =
    session.status === "acquired" ? session.record.customer_id : null;

  useEffect(() => {
    if (!activeCustomerId) {
      return;
    }

    const customerId = activeCustomerId;
    let active = true;

    async function loadCustomerReference() {
      try {
        const { data, error } = await supabase.rpc("get_case_queue");
        if (error) throw error;

        const row = (
          (data ?? []) as Array<{
            case_id: string;
            customer_reference: string | null;
          }>
        ).find((item) => item.case_id === caseId);

        if (!row?.customer_reference) {
          throw new Error("Customer reference not found");
        }

        if (active) {
          setCustomerReference({
            caseId,
            customerId,
            reference: row.customer_reference,
          });
          setCustomerReferenceError(null);
        }
      } catch {
        if (active) {
          setCustomerReferenceError({ caseId, customerId });
        }
      }
    }

    void loadCustomerReference();

    return () => {
      active = false;
    };
  }, [caseId, activeCustomerId]);

  const leaveSessionRef = useRef<null | (() => Promise<boolean>)>(null);
  const leavingRef = useRef(false);
  const router = useRouter();
  const [leaveError, setLeaveError] = useState<string | null>(null);
  const [checkingEvidenceBeforeLeave, setCheckingEvidenceBeforeLeave] =
    useState(false);
  const [employeeId, setEmployeeId] = useState<string | null>(null);
  const [assigneeName, setAssigneeName] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saveMessage, setSaveMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!saveMessage) return;

    const timer = window.setTimeout(() => {
      setSaveMessage(null);
    }, 2000);

    return () => window.clearTimeout(timer);
  }, [saveMessage]);

  const [saving, setSaving] = useState(false);
  const savingRef = useRef(false);
  const [confirming, setConfirming] = useState(false);
  const updateOpenedRecordRef = useRef<null | ((id: string) => void)>(null);

  const [activityComments, setActivityComments] =
    useState<CaseActivityComment[]>([]);
  const [activityLoading, setActivityLoading] = useState(false);
  const [activityError, setActivityError] = useState<string | null>(null);
  const [activitySaving, setActivitySaving] = useState(false);
  const activitySavingRef = useRef(false);
  const activitySessionRef = useRef<string | null>(null);
  const activityRequestRef = useRef(0);
  const [caseEvidence, setCaseEvidence] = useState<CaseEvidenceAttachment[]>([]);
  const [evidenceLoading, setEvidenceLoading] = useState(false);
  const [evidenceError, setEvidenceError] = useState<string | null>(null);
  const evidenceRequestRef = useRef(0);

  const [activeCaseTab, setActiveCaseTab] =
    useState<"record" | "audit">("record");
  const [auditEvents, setAuditEvents] = useState<CaseAuditEvent[]>([]);
  const [auditLoading, setAuditLoading] = useState(false);
  const [auditError, setAuditError] = useState<string | null>(null);
  const auditRequestRef = useRef(0);

  async function loadAuditHistory(lockToken: string) {
    const requestId = ++auditRequestRef.current;

    const isCurrentRequest = () =>
      activitySessionRef.current === lockToken &&
      auditRequestRef.current === requestId &&
      !leavingRef.current;

    if (!isCurrentRequest()) return;

    setAuditLoading(true);
    setAuditError(null);

    try {
      const { data, error } = await supabase.rpc(
        "get_employee_case_audit_history",
        {
          p_case_id: caseId,
          p_lock_token: lockToken,
        }
      );

      if (!isCurrentRequest()) return;

      if (error) {
        throw new Error(error.message);
      }

      setAuditEvents((data ?? []) as CaseAuditEvent[]);
    } catch (cause) {
      if (!isCurrentRequest()) return;

      setAuditError(
        cause instanceof Error
          ? cause.message
          : "Unable to load audit history."
      );
    } finally {
      if (isCurrentRequest()) {
        setAuditLoading(false);
      }
    }
  }

  const [downloadingEvidenceId, setDownloadingEvidenceId] =
    useState<string | null>(null);
  const [evidenceDownloadError, setEvidenceDownloadError] =
    useState<string | null>(null);
  const evidenceDownloadRef = useRef(false);

  async function handleEvidenceDownload(attachment: CaseEvidenceAttachment) {
    if (
      session.status !== "acquired" ||
      leavingRef.current ||
      evidenceDownloadRef.current
    ) {
      return;
    }

    const lockToken = session.token;
    evidenceDownloadRef.current = true;
    setDownloadingEvidenceId(attachment.id);
    setEvidenceDownloadError(null);

    try {
      const blob = await downloadCaseEvidence(
        caseId,
        lockToken,
        attachment.id
      );

      if (
        activitySessionRef.current !== lockToken ||
        leavingRef.current
      ) {
        throw new Error("Case access changed during download.");
      }

      const objectUrl = URL.createObjectURL(blob);

      try {
        const link = document.createElement("a");
        link.href = objectUrl;
        link.download = attachment.file_name;
        document.body.appendChild(link);

        try {
          link.click();
        } finally {
          link.remove();
        }
      } finally {
        URL.revokeObjectURL(objectUrl);
      }
    } catch (cause) {
      if (
        activitySessionRef.current === lockToken &&
        !leavingRef.current
      ) {
        setEvidenceDownloadError(
          cause instanceof Error
            ? cause.message
            : "Unable to download evidence."
        );
      }
    } finally {
      evidenceDownloadRef.current = false;
      setDownloadingEvidenceId(null);
    }
  }

  async function loadCaseEvidence(lockToken: string) {
    const requestId = ++evidenceRequestRef.current;

    const isCurrentRequest = () =>
      activitySessionRef.current === lockToken &&
      evidenceRequestRef.current === requestId &&
      !leavingRef.current;

    if (!isCurrentRequest()) return;

    setEvidenceLoading(true);
    setEvidenceError(null);

    try {
      const attachments = await getCaseEvidence(caseId, lockToken);

      if (!isCurrentRequest()) return;
      setCaseEvidence(attachments);
    } catch (cause) {
      if (!isCurrentRequest()) return;

      setEvidenceError(
        cause instanceof Error
          ? cause.message
          : "Unable to load case evidence."
      );
    } finally {
      if (isCurrentRequest()) {
        setEvidenceLoading(false);
      }
    }
  }

  async function loadActivityComments(lockToken: string) {
    const requestId = ++activityRequestRef.current;

    const isCurrentRequest = () =>
      activitySessionRef.current === lockToken &&
      activityRequestRef.current === requestId &&
      !leavingRef.current;

    if (!isCurrentRequest()) return;

    setActivityLoading(true);
    setActivityError(null);

    try {
      const { data, error } = await supabase.rpc(
        "get_employee_case_comments",
        {
          p_case_id: caseId,
          p_lock_token: lockToken,
        }
      );

      if (!isCurrentRequest()) return;

      if (error) {
        throw new Error(error.message);
      }

      setActivityComments((data ?? []) as CaseActivityComment[]);
    } catch (cause) {
      if (!isCurrentRequest()) return;

      setActivityError(
        cause instanceof Error
          ? cause.message
          : "Unable to load case activity."
      );
    } finally {
      if (isCurrentRequest()) {
        setActivityLoading(false);
      }
    }
  }

  async function loadAssignmentDetails(record: CaseRecord) {
    setSaveError(null);

    const { data: currentEmployee, error: employeeError } =
      await supabase.rpc("current_employee_id");

    if (employeeError || !currentEmployee) {
      setSaveError("Unable to verify your employee identity.");
      return;
    }

    setEmployeeId(currentEmployee);

    if (record.assigned_user_id) {
      const { data: assignee, error: assigneeError } = await supabase
        .from("users")
        .select("full_name")
        .eq("id", record.assigned_user_id)
        .single();

      if (assigneeError || !assignee) {
        setSaveError("Unable to identify the assigned employee.");
        return;
      }

      setAssigneeName(assignee.full_name);
    } else {
      setAssigneeName(null);
    }
  }

  async function handleSave(confirmed = false) {
    if (
      session.status !== "acquired" ||
      savingRef.current ||
      leavingRef.current ||
      !employeeId
    ) return;

    const previousAssignee = session.record.assigned_user_id;

    if (previousAssignee && previousAssignee !== employeeId && !confirmed) {
      setSaveMessage(null);
      setSaveError(null);
      setConfirming(true);
      return;
    }

    savingRef.current = true;
    setSaving(true);
    setSaveError(null);
    setSaveMessage(null);

    try {
      const { error } = await supabase.rpc("save_employee_case_assignment", {
        p_case_id: caseId,
        p_lock_token: session.token,
        p_expected_assigned_user_id: previousAssignee,
        p_confirm_reassignment: confirmed,
      });

      if (error) {
        setSaveError(error.message);
        return;
      }

      updateOpenedRecordRef.current?.(employeeId);
      setSession((current) =>
        current.status === "acquired"
          ? {
              ...current,
              record: {
                ...current.record,
                assigned_user_id: employeeId,
              },
            }
          : current
      );

      const { data: employee } = await supabase
        .from("users")
        .select("full_name")
        .eq("id", employeeId)
        .single();

      setAssigneeName(employee?.full_name ?? "You");
      setSaveMessage("Case responsibility saved successfully.");
      setConfirming(false);
    } catch {
      setSaveError("Unable to save case responsibility. Please try again.");
    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  }

  async function handleSaveActivity(body: string): Promise<string> {
    if (
      session.status !== "acquired" ||
      activitySavingRef.current ||
      leavingRef.current
    ) {
      throw new Error(
        "Exclusive case access is unavailable. Please reopen the case."
      );
    }

    const lockToken = session.token;

    activitySavingRef.current = true;
    setActivitySaving(true);
    setActivityError(null);

    try {
      const { data: commentId, error } = await supabase.rpc(
        "save_employee_case_comment",
        {
          p_case_id: caseId,
          p_lock_token: lockToken,
          p_body: body,
        }
      );

      if (error) {
        throw new Error(error.message);
      }

      if (!commentId || typeof commentId !== "string") {
        throw new Error(
          "Comment save returned no ID. Check the activity record before retrying."
        );
      }

      // The comment is committed. Refreshing the activity list must
      // never invalidate the returned ID or cause a duplicate submission.
      void loadActivityComments(lockToken);
      void loadAuditHistory(lockToken);
      return commentId;
    } finally {
      activitySavingRef.current = false;
      setActivitySaving(false);
    }
  }

  async function handleBack() {
    if (leavingRef.current || savingRef.current || activitySavingRef.current) return;

    leavingRef.current = true;
    setCheckingEvidenceBeforeLeave(true);

    if (session.status === "acquired") {
      try {
        const reservations =
          await listEmployeeCaseEvidenceUploadReservations(
            caseId,
            session.token
          );

        const unresolved = reservations.filter(
          (reservation) => reservation.reservation_status !== "completed"
        );

        if (unresolved.length > 0) {
          const confirmed = window.confirm(
            `${unresolved.length} evidence upload reservation(s) require review. ` +
              "Leaving will release your case lock, but will not resolve or " +
              "delete these reservations. Further evidence uploads may remain " +
              "blocked until recovery is completed. Leave this case?"
          );

          if (!confirmed) {
            leavingRef.current = false;
            setCheckingEvidenceBeforeLeave(false);
            return;
          }
        }
      } catch {
        // Work-permission revocation blocks evidence reservation discovery.
        // It must not prevent the existing owner-verified lock release.
        let workPermissionUnavailable = false;

        try {
          const { data, error } = await supabase.rpc("can_work_on_case", {
            p_case_id: caseId,
          });

          workPermissionUnavailable = !error && data === false;
        } catch {
          workPermissionUnavailable = false;
        }

        if (!workPermissionUnavailable) {
          setLeaveError(
            "Unable to verify outstanding evidence uploads. " +
              "Please retry before leaving this case."
          );
          leavingRef.current = false;
          setCheckingEvidenceBeforeLeave(false);
          return;
        }

        // Outstanding reservations cannot be inspected after access loss.
        // They are not modified. Navigation still requires successful
        // close_case_session verification below.
      }
    }

    setCheckingEvidenceBeforeLeave(false);
    activitySessionRef.current = null;
    activityRequestRef.current += 1;
    auditRequestRef.current += 1;
    setLeaveError(null);
    let navigationStarted = false;

    try {
      const leave = leaveSessionRef.current;

      if (!leave || !(await leave())) {
        setLeaveError("Could not confirm the case was released. Please try again.");
        return;
      }

      navigationStarted = true;
      setActiveCaseTab("record");
      setSaveMessage(null);
      setSaveError(null);
      setConfirming(false);
      router.push("/cases");
      router.refresh();
    } catch {
      setLeaveError("Unable to leave the case safely. Please try again.");
    } finally {
      leavingRef.current = false;

      // Recover activity only when the employee remains on this page.
      // The database validates whether the lock is still owned.
      if (!navigationStarted && session.status === "acquired") {
        activitySessionRef.current = session.token;
        void loadActivityComments(session.token);
        void loadCaseEvidence(session.token);
        void loadAuditHistory(session.token);
      }
    }
  }

  useEffect(() => {
    let active = true;
    let lockToken: string | null = null;
    let openedRecord: CaseRecord | null = null;
    let renewalTimer: ReturnType<typeof setTimeout> | null = null;
    let expiryTimer: ReturnType<typeof setTimeout> | null = null;

    function invalidateActivityAccess() {
      activitySessionRef.current = null;
      activityRequestRef.current += 1;
      evidenceRequestRef.current += 1;
      auditRequestRef.current += 1;
      setActivityLoading(false);
      setActivityComments([]);
      setEvidenceLoading(false);
      setCaseEvidence([]);
      setEvidenceError(null);
      setEvidenceDownloadError(null);
      setAuditLoading(false);
      setAuditEvents([]);
    }

    function scheduleExpiryCheck(expiresAt: string) {
      if (!active) return;

      if (expiryTimer) clearTimeout(expiryTimer);

      const delay = Math.max(
        0,
        Date.parse(expiresAt) - Date.now()
      );

      expiryTimer = setTimeout(() => {
        if (!active) return;

        invalidateActivityAccess();
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
            invalidateActivityAccess();
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
          invalidateActivityAccess();
          setSession({ status: "verification_required" });
          return;
        }

        const confirmedRecord = openedRecord;

        // Restore activity access only after the existing renewal
        // validation has confirmed the lock remains valid.
        if (activitySessionRef.current !== token) {
          activitySessionRef.current = token;
          void loadActivityComments(token);
          void loadCaseEvidence(token);
          void loadAuditHistory(token);
        }

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

      const { data: identity, error: identityError } =
        await supabase.auth.getUser();

      if (!active) return;

      if (identityError || !identity.user) {
        setSession({ status: "error" });
        return;
      }

      const authUserId = identity.user.id;
      const savedToken = readSavedCaseSession(caseId, authUserId);

      let acquiredToken: string | null = null;
      let expiresAt: string | null = null;
      let resumed = false;

      if (savedToken) {
        const { data: verifiedExpiry, error: resumeError } =
          await supabase.rpc("resume_employee_case_session", {
            p_case_id: caseId,
            p_lock_token: savedToken,
          });

        if (!active) return;

        if (
          !resumeError &&
          verifiedExpiry &&
          Number.isFinite(Date.parse(verifiedExpiry)) &&
          Date.parse(verifiedExpiry) > Date.now()
        ) {
          acquiredToken = savedToken;
          expiresAt = verifiedExpiry;
          resumed = true;
        } else {
          clearSavedCaseSession(caseId, savedToken);
        }
      }

      if (!acquiredToken) {
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

        acquiredToken = result.lock_token;
        expiresAt = result.lock_expires_at;
      }

      if (!acquiredToken || !expiresAt) {
        if (active) setSession({ status: "error" });
        return;
      }

      const confirmedToken: string = acquiredToken;
      lockToken = confirmedToken;

      if (!active) {
        if (!resumed) {
          lockToken = null;
          await releaseSession(confirmedToken);
        }
        return;
      }

      const { data: caseData, error: detailsError } =
        await supabase.rpc("get_locked_case_details", {
          p_case_id: caseId,
          p_lock_token: confirmedToken,
        });

      if (!active) return;

      const record = caseData?.[0] as CaseRecord | undefined;

      if (detailsError || !record || !expiresAt) {
        setSession({ status: "error" });

        if (!resumed) {
          lockToken = null;
          await releaseSession(confirmedToken);
        }
        return;
      }

      openedRecord = record;
      void loadAssignmentDetails(record);

      saveCaseSession(caseId, authUserId, confirmedToken);

      setSession({
        status: "acquired",
        token: confirmedToken,
        expiresAt,
        record,
      });

      activitySessionRef.current = confirmedToken;
      void loadActivityComments(confirmedToken);
      void loadCaseEvidence(confirmedToken);
      void loadAuditHistory(confirmedToken);

      scheduleExpiryCheck(expiresAt);
      scheduleRenewal(confirmedToken, expiresAt);
    }

    updateOpenedRecordRef.current = (assignedUserId: string) => {
      if (openedRecord) {
        openedRecord = {
          ...openedRecord,
          assigned_user_id: assignedUserId,
        };
      }
    };

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
        // React cleanup and browser refresh do not release the lock.
        // The existing token remains available for verified recovery.
        // Explicit Back navigation performs the database release.
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

        if (!lockToken) {
          return releaseConfirmed;
        }

        const token = lockToken;
        releaseConfirmed = await releaseSession(token);

        if (releaseConfirmed) {
          lockToken = null;
          clearSavedCaseSession(caseId, token);
        }

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
      updateOpenedRecordRef.current = null;
      activitySessionRef.current = null;
      activityRequestRef.current += 1;
      auditRequestRef.current += 1;
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
          disabled={saving || activitySaving || checkingEvidenceBeforeLeave}
          className="text-sm text-[#51483F] hover:underline disabled:opacity-50"
        >
          ← Back to cases
        </button>

        {leaveError && (
          <p role="alert" className="mt-3 text-sm text-red-700">
            {leaveError}
          </p>
        )}

        <header className="mt-6 border-b border-[#D8CBB8] pb-5">
          <h1 className="text-2xl font-semibold">
            {session.status === "acquired"
              ? `Case ${session.record.case_reference}`
              : "Opening case…"}
          </h1>

          {session.status === "acquired" && (
            <>
              <h2 className="mt-2 text-lg font-medium">
                {session.record.title}
              </h2>
              <p className="mt-2 text-sm text-[#756B60]">
                Status: {session.record.status.replaceAll("_", " ")}
              </p>
            </>
          )}
        </header>

        {session.status === "loading" && (
          <div
            aria-label="Loading case workspace"
            aria-busy="true"
            className={`mt-6 transition-opacity duration-150 ${
              showLoadingSkeleton ? "opacity-100" : "opacity-0"
            }`}
          >
            <div className="mb-5 flex gap-4 border-b border-[#D8CBB8] pb-3">
              <div className="h-4 w-24 animate-pulse rounded bg-[#EAE4DA]" />
              <div className="h-4 w-24 animate-pulse rounded bg-[#EAE4DA]" />
            </div>
            <div className="rounded-xl border border-[#E4DCD0] p-5">
              <div className="mb-5 h-4 w-40 animate-pulse rounded bg-[#EAE4DA]" />
              <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
                {[0, 1, 2, 3].map((item) => (
                  <div key={item} className="space-y-2">
                    <div className="h-3 w-20 animate-pulse rounded bg-[#EAE4DA]" />
                    <div className="h-4 w-36 max-w-full animate-pulse rounded bg-[#EAE4DA]" />
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {session.status !== "loading" &&
          session.status !== "acquired" && (
            <p className="mt-4 text-sm text-[#756B60]">
              {session.status === "locked"
                ? "This case is currently locked in another session."
                : session.status === "verification_required"
                  ? "Exclusive access needs verification. Protected actions are unavailable until access is restored."
                  : "Unable to open this case. Please return to the case queue."}
            </p>
          )}

        {session.status === "acquired" && (
          <nav aria-label="Case sections" className="mt-6 flex gap-6 border-b border-[#D8CBB8]">
            {(["record", "audit"] as const).map((tab) => (
              <button
                key={tab}
                type="button"
                role="tab"
                aria-selected={activeCaseTab === tab}
                aria-controls={tab === "record" ? "case-record-panel" : "case-audit-panel"}
                id={tab === "record" ? "case-record-tab" : "case-audit-tab"}
                onClick={() => {
                  setActiveCaseTab(tab);
                  if (tab === "audit") void loadAuditHistory(session.token);
                }}
                className={`border-b-2 px-1 pb-3 text-sm ${
                  activeCaseTab === tab
                    ? "border-[#51483F] font-semibold text-[#39352F]"
                    : "border-transparent text-[#756B60] hover:text-[#39352F]"
                }`}
              >
                {tab === "record" ? "Case Record" : "Audit History"}
              </button>
            ))}
          </nav>
        )}

        {session.status === "acquired" && activeCaseTab === "record" && (
          <section id="case-record-panel" role="tabpanel" aria-labelledby="case-record-tab" className="mt-8 overflow-hidden rounded-lg border border-[#D8CBB8] bg-white">
            <div className="flex flex-wrap items-center justify-between gap-4 border-b border-[#D8CBB8] bg-[#EAE4D9] px-5 py-3">
              <h3 className="text-sm font-semibold">Case Information</h3>

              <div className="flex flex-wrap items-center gap-4">
                <div className="text-right">
                  <p className="text-xs text-[#756B60]">Case Owner</p>
                  <p className="mt-1 text-sm font-semibold">
                    {session.record.assigned_user_id
                      ? assigneeName ?? "Loading employee..."
                      : "Unassigned"}
                  </p>
                </div>

                <button
                  type="button"
                  onClick={() => void handleSave()}
                  disabled={
                    saving ||
                    !employeeId ||
                    (session.record.assigned_user_id !== null &&
                      assigneeName === null)
                  }
                  className="rounded-md bg-[#39352F] px-5 py-2 text-sm font-medium text-white disabled:opacity-50"
                >
                  {saving ? "Saving..." : "Save"}
                </button>
              </div>
            </div>

        {confirming && session.status === "acquired" && (
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="reassignment-title"
            className="mx-5 my-4 rounded-lg border border-[#D8CBB8] bg-[#FAF8F4] p-5"
          >
            <h2 id="reassignment-title" className="font-semibold">
              Confirm case reassignment
            </h2>
            <p className="mt-2 text-sm">
              This case is assigned to{" "}
              <strong>{assigneeName ?? "another employee"}</strong>.
              {" "}Reassign it to yourself?
            </p>
            <div className="mt-4 flex gap-3">
              <button
                type="button"
                onClick={() => setConfirming(false)}
                disabled={saving}
                className="rounded-md border px-4 py-2 text-sm"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => void handleSave(true)}
                disabled={saving}
                className="rounded-md bg-[#39352F] px-4 py-2 text-sm text-white disabled:opacity-50"
              >
                {saving ? "Saving..." : "Confirm reassignment"}
              </button>
            </div>
          </div>
        )}

            {(saveMessage || saveError ||
              employeeId === null ||
              (session.record.assigned_user_id !== null &&
                assigneeName === null)) && (
              <div className="space-y-2 border-b border-[#EAE4D9] px-6 py-3">
                {saveMessage && (
                  <p role="status" className="text-sm text-green-700">
                    {saveMessage}
                  </p>
                )}

                {saveError && (
                  <p role="alert" className="text-sm text-red-700">
                    {saveError}
                  </p>
                )}

                {(employeeId === null ||
                  (session.record.assigned_user_id !== null &&
                    assigneeName === null)) && (
                  <button
                    type="button"
                    onClick={() => void loadAssignmentDetails(session.record)}
                    disabled={saving}
                    className="text-sm text-[#51483F] underline disabled:opacity-50"
                  >
                    Retry employee details
                  </button>
                )}
              </div>
            )}

            <dl className="space-y-5 px-6 py-6">
              {[
                ["Created on", new Date(session.record.created_at).toLocaleString("en-GB", {
                  dateStyle: "medium",
                  timeStyle: "short",
                  timeZone: "Europe/London",
                })],
                ["Case type", session.record.case_type?.replaceAll("_", " ") ?? "Not specified"],
                ["Source", session.record.source.replaceAll("_", " ")],
                ["Initiated by", session.record.initiated_by ?? "Not specified"],
                ["Customer reference", !session.record.customer_id
                  ? "No customer linked"
                  : customerReference?.caseId === caseId &&
                      customerReference.customerId === session.record.customer_id
                    ? customerReference.reference
                    : customerReferenceError?.caseId === caseId &&
                      customerReferenceError.customerId === session.record.customer_id
                      ? "Reference unavailable"
                      : "Loading reference…"],
                ["Assigned team reference", session.record.assigned_team_id ?? "Unassigned"],
                ["Priority", session.record.priority.replaceAll("_", " ")],
              ].map(([label, value]) => (
                <div key={label}>
                  <dt className="text-xs font-medium text-[#756B60]">{label}</dt>
                  <dd className="mt-1 text-sm font-medium text-[#39352F]">{value}</dd>
                </div>
              ))}

              <div className="border-t border-[#EAE4D9] pt-5">
                <dt className="text-xs font-medium text-[#756B60]">
                  Description / Initial comment
                </dt>
                <dd className="mt-2 whitespace-pre-wrap text-sm leading-6 text-[#39352F]">
                  {session.record.description || "No description provided."}
                </dd>
              </div>
            </dl>
          </section>
        )}

        {session.status === "acquired" && activeCaseTab === "record" && (
          <section className="mt-8 rounded-lg border border-[#D8CBB8] bg-white p-6">
            <div className="grid grid-cols-[1fr_auto] items-center gap-4">
              <div>
                <h3 className="text-lg font-semibold">Case Activity</h3>
                <p className="mt-1 text-sm text-[#756B60]">
                  Internal work updates and handover comments.
                </p>
              </div>
              <CaseActivityEditor
                  onSave={handleSaveActivity}
                  onEvidenceUploadActiveChange={(active) => {
                    activitySavingRef.current = active;
                    setActivitySaving(active);
                  }}
                  onEvidenceUploaded={() => {
                    if (session.status === "acquired") {
                      void loadCaseEvidence(session.token);
                      void loadAuditHistory(session.token);
                    }
                  }}
                  caseId={caseId}
                  lockToken={session.token}
                />
            </div>

            {activityError && (
              <p role="alert" className="mt-4 text-sm text-red-700">
                {activityError}
              </p>
            )}

            {caseEvidence.some(
                (attachment) => attachment.comment_id === null
              ) && (
                <section className="mt-4 rounded-lg border border-[#EAE4D9] bg-[#FAF9F6] p-3">
                  <h4 className="text-sm font-semibold text-[#39352F]">
                    Other Case Evidence
                  </h4>
                  <p className="mt-1 text-xs text-[#756B60]">
                    Finalised attachments not linked to an activity comment.
                  </p>
                  <ul className="mt-4 space-y-3">
                    {caseEvidence
                      .filter((attachment) => attachment.comment_id === null)
                      .map((attachment) => (
                        <li
                          key={attachment.id}
                          className="rounded-md border border-[#EAE4D9] bg-white px-3 py-2"
                        >
                          <p className="break-words text-sm font-medium leading-5 text-[#39352F]">
                            {attachment.file_name}
                          </p>
                          <p className="mt-1 text-xs text-[#756B60]">
                            {attachment.uploaded_by_name}
                            {" · "}
                            {new Date(attachment.created_at).toLocaleString(
                              "en-GB",
                              {
                                dateStyle: "medium",
                                timeStyle: "short",
                                timeZone: "Europe/London",
                              }
                            )}
                            {" · "}
                            {(attachment.file_size_bytes / 1024).toFixed(1)}
                            {" KB"}
                          </p>
                          <button
                            type="button"
                            onClick={() =>
                              void handleEvidenceDownload(attachment)
                            }
                            disabled={downloadingEvidenceId !== null}
                            className="mt-2 rounded-md border border-[#C9BBA7] px-2.5 py-1 text-xs font-medium text-[#39352F] hover:bg-[#F4F0E9] disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            {downloadingEvidenceId === attachment.id
                              ? "Downloading..."
                              : "Download"}
                          </button>
                        </li>
                      ))}
                  </ul>
                </section>
              )}

              {evidenceDownloadError && (
                <p role="alert" className="mt-4 text-sm text-red-700">
                  Evidence download failed: {evidenceDownloadError}
                </p>
              )}

              {evidenceLoading && (
                <p role="status" className="mt-4 text-sm text-[#756B60]">
                  Loading supporting evidence...
                </p>
              )}

              {evidenceError && (
                <div className="mt-4">
                  <p role="alert" className="text-sm text-red-700">
                    Supporting evidence could not be loaded: {evidenceError}
                  </p>
                  <button
                    type="button"
                    onClick={() => void loadCaseEvidence(session.token)}
                    className="mt-2 text-sm text-[#51483F] underline"
                  >
                    Retry evidence loading
                  </button>
                </div>
              )}

              {activityLoading ? (
              <p className="mt-6 text-sm text-[#756B60]">
                Loading case activity...
              </p>
            ) : activityComments.length === 0 ? (
              <p className="mt-6 text-sm text-[#756B60]">
                {caseEvidence.length > 0
                  ? "No written updates yet. Supporting evidence is shown above."
                  : "No internal activity recorded yet."}
              </p>
            ) : (
              <div className="mt-4 space-y-2">
                {activityComments.map((activity) => (
                  <article
                    key={activity.id}
                    className="rounded-lg border border-[#EAE4D9] bg-[#FAF9F6] px-4 py-3"
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <p className="text-sm font-semibold">
                        {activity.author_name}
                      </p>
                      <time
                        dateTime={activity.created_at}
                        className="text-xs text-[#756B60]"
                      >
                        {new Date(activity.created_at).toLocaleString(
                          "en-GB",
                          {
                            dateStyle: "medium",
                            timeStyle: "short",
                            timeZone: "Europe/London",
                          }
                        )}
                      </time>
                    </div>
                    <p className="mt-2 whitespace-pre-wrap break-words text-sm leading-5 text-[#39352F]">
                      {activity.body}
                    </p>

                    <div className="mt-4 flex justify-end">
                      <CaseActivityEditor
                        existingCommentId={activity.id}
                        onSave={handleSaveActivity}
                        onEvidenceUploadActiveChange={(active) => {
                          activitySavingRef.current = active;
                          setActivitySaving(active);
                        }}
                        onEvidenceUploaded={() => {
                          if (session.status === "acquired") {
                            void loadCaseEvidence(session.token);
                            void loadAuditHistory(session.token);
                          }
                        }}
                        caseId={caseId}
                        lockToken={session.token}
                      />
                    </div>

                      {caseEvidence.filter(
                        (attachment) => attachment.comment_id === activity.id
                      ).length > 0 && (
                        <div className="mt-4 border-t border-[#EAE4D9] pt-4">
                          <p className="mb-3 text-xs font-semibold uppercase tracking-wide text-[#756B60]">
                            Supporting Evidence
                          </p>
                          <ul className="space-y-3">
                            {caseEvidence
                              .filter(
                                (attachment) =>
                                  attachment.comment_id === activity.id
                              )
                              .map((attachment) => (
                                <li
                                  key={attachment.id}
                                  className="rounded-md border border-[#EAE4D9] bg-white px-3 py-2"
                                >
                                  <p className="break-words text-sm font-medium leading-5 text-[#39352F]">
                                    {attachment.file_name}
                                  </p>
                                  <p className="mt-1 text-xs text-[#756B60]">
                                    {attachment.uploaded_by_name}
                                    {" · "}
                                    {new Date(
                                      attachment.created_at
                                    ).toLocaleString("en-GB", {
                                      dateStyle: "medium",
                                      timeStyle: "short",
                                      timeZone: "Europe/London",
                                    })}
                                    {" · "}
                                    {(attachment.file_size_bytes / 1024).toFixed(1)}
                                    {" KB"}
                                  </p>

                                  <button
                                    type="button"
                                    onClick={() =>
                                      void handleEvidenceDownload(attachment)
                                    }
                                    disabled={downloadingEvidenceId !== null}
                                    className="mt-2 rounded-md border border-[#C9BBA7] px-2.5 py-1 text-xs font-medium text-[#39352F] hover:bg-[#F4F0E9] disabled:cursor-not-allowed disabled:opacity-50"
                                  >
                                    {downloadingEvidenceId === attachment.id
                                      ? "Downloading..."
                                      : "Download"}
                                  </button>
                                </li>
                              ))}
                          </ul>
                        </div>
                      )}
                  </article>
                ))}
              </div>
            )}
          </section>
        )}

        {session.status === "acquired" && activeCaseTab === "audit" && (
          <section
            id="case-audit-panel"
            role="tabpanel"
            aria-labelledby="case-audit-tab"
            className="mt-8 rounded-lg border border-[#D8CBB8] bg-white p-6"
          >
            <h3 className="text-lg font-semibold">Audit History</h3>
            <p className="mt-1 text-sm text-[#756B60]">
              Recorded case access, assignment and information changes.
            </p>

            {auditError && (
              <div className="mt-4">
                <p role="alert" className="text-sm text-red-700">{auditError}</p>
                <button
                  type="button"
                  onClick={() => void loadAuditHistory(session.token)}
                  className="mt-2 text-sm text-[#51483F] underline"
                >
                  Retry audit history
                </button>
              </div>
            )}

            {auditLoading ? (
              <p className="mt-6 text-sm text-[#756B60]">Loading audit history...</p>
            ) : auditEvents.length === 0 && !auditError ? (
              <p className="mt-6 text-sm text-[#756B60]">
                No audit events recorded for this case.
              </p>
            ) : (
              <div className="mt-6 overflow-x-auto rounded-md border border-[#EAE4D9]">
                <table className="w-full min-w-[760px] border-collapse text-left text-sm">
                  <thead className="bg-[#F4F0E9] text-xs font-semibold text-[#756B60]">
                    <tr>
                      <th scope="col" className="px-4 py-3">Date &amp; Time</th>
                      <th scope="col" className="px-4 py-3">Action</th>
                      <th scope="col" className="px-4 py-3">Employee</th>
                      <th scope="col" className="px-4 py-3">Details</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#EAE4D9]">
                    {auditEvents.map((event) => {
                      const labels: Record<string, string> = {
                        case_created: "Case created",
                        case_opened: "Case opened",
                        case_closed_view: "Case view closed",
                        case_updated: "Case updated",
                        case_information_updated: "Case information updated",
                          comment_added: "Comment added",
                      };

                      const changes = [
                        event.from_status !== event.to_status &&
                        (event.from_status || event.to_status)
                          ? `Status: ${event.from_status ?? "None"} → ${event.to_status ?? "None"}`
                          : null,
                        event.from_user_name !== event.to_user_name &&
                        (event.from_user_name || event.to_user_name)
                          ? `Case owner: ${event.from_user_name ?? "Unassigned"} → ${event.to_user_name ?? "Unassigned"}`
                          : null,
                        event.from_team_name !== event.to_team_name &&
                        (event.from_team_name || event.to_team_name)
                          ? `Team: ${event.from_team_name ?? "Unassigned"} → ${event.to_team_name ?? "Unassigned"}`
                          : null,
                        event.details,
                      ].filter((detail): detail is string => Boolean(detail));

                      return (
                        <tr key={event.id} className="hover:bg-[#FAF9F6]">
                          <td className="whitespace-nowrap px-4 py-3 text-xs text-[#756B60]">
                            <time dateTime={event.created_at}>
                              {new Date(event.created_at).toLocaleString("en-GB", {
                                dateStyle: "medium",
                                timeStyle: "short",
                                timeZone: "Europe/London",
                              })}
                            </time>
                          </td>
                          <td className="whitespace-nowrap px-4 py-3 font-medium">
                            {labels[event.event_type] ??
                              event.event_type.replaceAll("_", " ")}
                          </td>
                          <td className="px-4 py-3">{event.actor_name}</td>
                          <td className="px-4 py-3">
                            {changes.length > 0 ? (
                              <details>
                                <summary className="cursor-pointer text-[#51483F] hover:underline">
                                  View details ({changes.length})
                                </summary>
                                <ul className="mt-2 space-y-1 text-xs text-[#756B60]">
                                  {changes.map((change, index) => (
                                    <li key={index} className="break-words">
                                      {change}
                                    </li>
                                  ))}
                                </ul>
                              </details>
                            ) : (
                              <span className="text-xs text-[#9A9084]">—</span>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        )}


      </div>
    </main>
  );
}
