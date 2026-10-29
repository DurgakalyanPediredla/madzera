const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const sourcePath = path.resolve(
  __dirname,
  "../src/app/cases/[caseId]/CaseWorkspace.tsx"
);

function extractHandleBack() {
  const source = fs.readFileSync(sourcePath, "utf8");
  const marker = "  async function handleBack() {";
  const start = source.indexOf(marker);

  assert.notEqual(start, -1, "Actual handleBack function must exist");
  assert.equal(
    source.indexOf(marker, start + marker.length),
    -1,
    "Exactly one handleBack function is required"
  );

  const openingBrace = source.indexOf("{", start);
  let depth = 0;
  let end = -1;

  for (let i = openingBrace; i < source.length; i++) {
    if (source[i] === "{") depth++;
    if (source[i] === "}") {
      depth--;
      if (depth === 0) {
        end = i + 1;
        break;
      }
    }
  }

  assert.notEqual(end, -1, "handleBack must have a closing brace");

  return source.slice(start, end);
}

function createHarness({
  reservations = [],
  reservationError = false,
  permission = true,
  permissionError = false,
  release = true,
  confirmation = true,
} = {}) {
  const calls = [];
  const errors = [];
  const session = {
    status: "acquired",
    token: "test-lock-token",
  };

  const leavingRef = { current: false };
  const savingRef = { current: false };
  const activitySavingRef = { current: false };
  const activitySessionRef = { current: session.token };
  const activityRequestRef = { current: 0 };
  const auditRequestRef = { current: 0 };

  const context = {
    caseId: "test-case-id",
    session,
    leavingRef,
    savingRef,
    activitySavingRef,
    activitySessionRef,
    activityRequestRef,
    auditRequestRef,

    setCheckingEvidenceBeforeLeave: (value) =>
      calls.push(["checking", value]),
    setLeaveError: (value) => {
      errors.push(value);
      calls.push(["leaveError", value]);
    },
    setActiveCaseTab: () => {},
    setSaveMessage: () => {},
    setSaveError: () => {},
    setConfirming: () => {},

    listEmployeeCaseEvidenceUploadReservations: async () => {
      calls.push(["reservations"]);
      if (reservationError) throw new Error("Reservation discovery failed");
      return reservations;
    },

    supabase: {
      rpc: async (name) => {
        calls.push(["rpc", name]);

        if (name !== "can_work_on_case") {
          throw new Error("Unexpected RPC: " + name);
        }

        if (permissionError) {
          return { data: null, error: { message: "Permission check failed" } };
        }

        return { data: permission, error: null };
      },
    },

    window: {
      confirm: () => {
        calls.push(["confirm"]);
        return confirmation;
      },
    },

    leaveSessionRef: {
      current: async () => {
        calls.push(["release"]);
        return release;
      },
    },

    router: {
      push: (destination) => calls.push(["navigate", destination]),
      refresh: () => calls.push(["refresh"]),
    },

    loadActivityComments: async () => {},
    loadCaseEvidence: async () => {},
    loadAuditHistory: async () => {},
  };

  const extracted = extractHandleBack();

  vm.runInNewContext(
    extracted + "\nthis.runHandleBack = handleBack;",
    context,
    { timeout: 1000, filename: "CaseWorkspace.handleBack.tsx" }
  );

  return {
    run: () => context.runHandleBack(),
    calls,
    errors,
    leavingRef,
  };
}

test("normal exit checks reservations and releases lock", async () => {
  const h = createHarness();

  await h.run();

  assert.ok(h.calls.some((c) => c[0] === "reservations"));
  assert.ok(h.calls.some((c) => c[0] === "release"));
  assert.ok(h.calls.some((c) => c[0] === "navigate"));
  assert.equal(h.leavingRef.current, false);
});

test("unresolved reservation requires confirmation", async () => {
  const h = createHarness({
    reservations: [{ reservation_status: "pending" }],
    confirmation: false,
  });

  await h.run();

  assert.ok(h.calls.some((c) => c[0] === "confirm"));
  assert.ok(!h.calls.some((c) => c[0] === "release"));
  assert.ok(!h.calls.some((c) => c[0] === "navigate"));
});

test("revoked work permission allows verified lock release", async () => {
  const h = createHarness({
    reservationError: true,
    permission: false,
  });

  await h.run();

  assert.ok(
    h.calls.some((c) => c[0] === "rpc" && c[1] === "can_work_on_case")
  );
  assert.ok(h.calls.some((c) => c[0] === "release"));
  assert.ok(h.calls.some((c) => c[0] === "navigate"));
});

test("unexpected reservation error with valid permission blocks exit", async () => {
  const h = createHarness({
    reservationError: true,
    permission: true,
  });

  await h.run();

  assert.ok(!h.calls.some((c) => c[0] === "release"));
  assert.ok(!h.calls.some((c) => c[0] === "navigate"));
  assert.ok(h.errors.some((error) => typeof error === "string"));
});

test("failed permission verification blocks exit", async () => {
  const h = createHarness({
    reservationError: true,
    permissionError: true,
  });

  await h.run();

  assert.ok(!h.calls.some((c) => c[0] === "release"));
  assert.ok(!h.calls.some((c) => c[0] === "navigate"));
});

test("failed lock release prevents navigation", async () => {
  const h = createHarness({
    reservationError: true,
    permission: false,
    release: false,
  });

  await h.run();

  assert.ok(h.calls.some((c) => c[0] === "release"));
  assert.ok(!h.calls.some((c) => c[0] === "navigate"));
  assert.ok(
    h.errors.some((error) =>
      typeof error === "string" &&
      error.includes("Could not confirm the case was released")
    )
  );
});
