export type StoredEvidenceRecovery = {
  caseId: string;
  reservationId: string;
  fileName: string;
};

const STORAGE_PREFIX = "madzera:case-evidence-recovery:v2:";

function storageKey(reservationId: string): string {
  return STORAGE_PREFIX + reservationId;
}

export function saveEvidenceRecovery(
  record: StoredEvidenceRecovery
): void {
  if (typeof window === "undefined") return;

  window.sessionStorage.setItem(
    storageKey(record.reservationId),
    JSON.stringify(record)
  );
}

export function readEvidenceRecoveries(
  caseId: string
): StoredEvidenceRecovery[] {
  if (typeof window === "undefined") return [];

  const records: StoredEvidenceRecovery[] = [];

  for (let index = 0; index < window.sessionStorage.length; index += 1) {
    const key = window.sessionStorage.key(index);
    if (!key?.startsWith(STORAGE_PREFIX)) continue;

    const stored = window.sessionStorage.getItem(key);
    if (!stored) continue;

    try {
      const parsed: unknown = JSON.parse(stored);

      if (
        typeof parsed !== "object" ||
        parsed === null ||
        !("caseId" in parsed) ||
        !("reservationId" in parsed) ||
        !("fileName" in parsed) ||
        typeof parsed.caseId !== "string" ||
        typeof parsed.reservationId !== "string" ||
        typeof parsed.fileName !== "string" ||
        parsed.reservationId.length === 0 ||
        parsed.caseId !== caseId ||
        key !== storageKey(parsed.reservationId)
      ) {
        continue;
      }

      records.push({
        caseId: parsed.caseId,
        reservationId: parsed.reservationId,
        fileName: parsed.fileName,
      });
    } catch {
      // Ignore malformed records without deleting them.
    }
  }

  return records;
}

export function clearEvidenceRecovery(
  reservationId: string
): void {
  if (typeof window === "undefined") return;

  window.sessionStorage.removeItem(storageKey(reservationId));
}
