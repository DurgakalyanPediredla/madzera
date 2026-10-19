// Browser-tab recovery hint for an existing exclusive case lock.
// The database remains the authority for all lock ownership checks.

type SavedCaseSession = {
  caseId: string;
  authUserId: string;
  lockToken: string;
};

const STORAGE_KEY = "madzera:active-case-session:v1";

export function readSavedCaseSession(
  caseId: string,
  authUserId: string
): string | null {
  try {
    const raw = window.sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return null;

    const saved: unknown = JSON.parse(raw);

    if (
      typeof saved !== "object" ||
      saved === null ||
      !("caseId" in saved) ||
      !("authUserId" in saved) ||
      !("lockToken" in saved)
    ) {
      window.sessionStorage.removeItem(STORAGE_KEY);
      return null;
    }

    const session = saved as SavedCaseSession;

    if (
      session.caseId !== caseId ||
      session.authUserId !== authUserId ||
      typeof session.lockToken !== "string" ||
      session.lockToken.length === 0
    ) {
      window.sessionStorage.removeItem(STORAGE_KEY);
      return null;
    }

    return session.lockToken;
  } catch {
    return null;
  }
}

export function saveCaseSession(
  caseId: string,
  authUserId: string,
  lockToken: string
): void {
  try {
    window.sessionStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({ caseId, authUserId, lockToken })
    );
  } catch {
    // Browser storage may be unavailable; normal locking still works.
  }
}

export function clearSavedCaseSession(
  caseId: string,
  lockToken?: string
): void {
  try {
    const raw = window.sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return;

    const saved: unknown = JSON.parse(raw);

    if (
      typeof saved === "object" &&
      saved !== null &&
      "caseId" in saved &&
      saved.caseId === caseId &&
      (!lockToken ||
        ("lockToken" in saved && saved.lockToken === lockToken))
    ) {
      window.sessionStorage.removeItem(STORAGE_KEY);
    }
  } catch {
    try {
      window.sessionStorage.removeItem(STORAGE_KEY);
    } catch {
      // No storage access.
    }
  }
}
