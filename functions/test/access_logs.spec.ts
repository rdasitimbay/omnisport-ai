import * as admin from "firebase-admin";

const mockGet = jest.fn();
const mockSendEachForMulticast = jest.fn().mockResolvedValue({ successCount: 1, failureCount: 0 });

// Capture the handler passed to onDocumentCreated
let accessLogHandler: ((event: any) => Promise<void>) | null = null;

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentCreated: jest.fn((opts: any, handler: any) => {
    accessLogHandler = handler;
    return { __mocked_trigger: "onAccessLogCreated" };
  }),
}));

jest.mock("firebase-functions/v2/https", () => ({
  onCall: jest.fn(() => ({})),
  HttpsError: jest.fn(),
}));

jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: jest.fn(() => ({})),
}));

jest.mock("firebase-admin", () => {
  const mockDb = {
    collection: jest.fn().mockReturnThis(),
    doc: jest.fn().mockReturnThis(),
    get: mockGet,
  };
  const messagingMock = jest.fn().mockReturnValue({
    sendEachForMulticast: mockSendEachForMulticast,
  });
  return {
    firestore: jest.fn().mockReturnValue(mockDb),
    messaging: messagingMock,
    initializeApp: jest.fn(),
  };
});

// Import index to register the mocked functions and trigger
import "../src/index";

describe("onAccessLogCreated Firestore Cloud Trigger", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGet.mockReset();
  });

  it("sends real-time push notification to parent on ENTRY event", async () => {
    expect(accessLogHandler).not.toBeNull();

    // 1. Mock firestore get calls
    // First get: athlete document
    const mockAthleteDoc = {
      exists: true,
      data: () => ({
        full_name: "Juan Pérez",
        parentUid: "parent_123",
        teamOrCategory: "Voleibol",
      }),
    };

    // Second get: parent document
    const mockParentDoc = {
      exists: true,
      data: () => ({
        fcmToken: "mock_fcm_token_1_with_more_than_one_hundred_characters_long_abcdefghijklmnopqrstuvwxyz1234567890_extra_length_long_padding",
        fcmTokens: [
          "mock_fcm_token_2_with_more_than_one_hundred_characters_long_abcdefghijklmnopqrstuvwxyz1234567890_extra_length_long_padding",
        ],
      }),
    };

    // Third get: notification template config (app_config/notification_templates)
    const mockConfigDoc = {
      exists: false,
    };

    mockGet
      .mockResolvedValueOnce(mockAthleteDoc) // athletes/athlete_123
      .mockResolvedValueOnce(mockParentDoc)  // users/parent_123
      .mockResolvedValueOnce(mockConfigDoc);  // app_config/notification_templates

    // 2. Build mock event
    const event = {
      data: {
        data: () => ({
          athleteId: "athlete_123",
          eventType: "ENTRY",
        }),
      },
    };

    // 3. Invoke trigger handler
    await accessLogHandler!(event);

    // 4. Assertions
    expect(mockGet).toHaveBeenCalledTimes(3);
    expect(mockSendEachForMulticast).toHaveBeenCalledTimes(1);

    const callArgs = mockSendEachForMulticast.mock.calls[0][0];
    expect(callArgs.tokens).toContain("mock_fcm_token_1_with_more_than_one_hundred_characters_long_abcdefghijklmnopqrstuvwxyz1234567890_extra_length_long_padding");
    expect(callArgs.tokens).toContain("mock_fcm_token_2_with_more_than_one_hundred_characters_long_abcdefghijklmnopqrstuvwxyz1234567890_extra_length_long_padding");
    expect(callArgs.notification.title).toBe("Acceso Registrado");
    expect(callArgs.notification.body).toContain("Juan Pérez ha ingresado al entrenamiento de Voleibol");
  });

  it("sends real-time push notification to parent on EXIT event", async () => {
    expect(accessLogHandler).not.toBeNull();

    // 1. Mock firestore get calls
    const mockAthleteDoc = {
      exists: true,
      data: () => ({
        full_name: "Juan Pérez",
        parentUid: "parent_123",
        teamOrCategory: "Voleibol",
      }),
    };

    const mockParentDoc = {
      exists: true,
      data: () => ({
        fcmToken: "mock_fcm_token_1_with_more_than_one_hundred_characters_long_abcdefghijklmnopqrstuvwxyz1234567890_extra_length_long_padding",
      }),
    };

    const mockConfigDoc = {
      exists: false,
    };

    mockGet
      .mockResolvedValueOnce(mockAthleteDoc)
      .mockResolvedValueOnce(mockParentDoc)
      .mockResolvedValueOnce(mockConfigDoc);

    // 2. Build mock event
    const event = {
      data: {
        data: () => ({
          athleteId: "athlete_123",
          eventType: "EXIT",
        }),
      },
    };

    // 3. Invoke trigger handler
    await accessLogHandler!(event);

    // 4. Assertions
    expect(mockGet).toHaveBeenCalledTimes(3);
    expect(mockSendEachForMulticast).toHaveBeenCalledTimes(1);

    const callArgs = mockSendEachForMulticast.mock.calls[0][0];
    expect(callArgs.tokens).toEqual(["mock_fcm_token_1_with_more_than_one_hundred_characters_long_abcdefghijklmnopqrstuvwxyz1234567890_extra_length_long_padding"]);
    expect(callArgs.notification.title).toBe("Salida Registrada");
    expect(callArgs.notification.body).toContain("Juan Pérez ha finalizado su sesión de Voleibol de forma segura.");
  });

  it("gracefully returns if athlete does not have a parentUid registered", async () => {
    expect(accessLogHandler).not.toBeNull();

    const mockAthleteDoc = {
      exists: true,
      data: () => ({
        full_name: "Juan Pérez",
        parentUid: undefined,
      }),
    };

    mockGet.mockResolvedValueOnce(mockAthleteDoc);

    const event = {
      data: {
        data: () => ({
          athleteId: "athlete_123",
          eventType: "ENTRY",
        }),
      },
    };

    await accessLogHandler!(event);

    expect(mockGet).toHaveBeenCalledTimes(1);
    expect(mockSendEachForMulticast).not.toHaveBeenCalled();
  });
});
