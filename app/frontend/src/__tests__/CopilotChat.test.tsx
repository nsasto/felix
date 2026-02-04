import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  render,
  screen,
  fireEvent,
  waitFor,
  act,
} from "@testing-library/react";
import CopilotChat from "../../components/CopilotChat";
import CopilotChatButton from "../../components/CopilotChatButton";
import CopilotChatPanel from "../../components/CopilotChatPanel";
import CopilotAvatar from "../../components/CopilotAvatar";
import type { AvatarState } from "../../components/CopilotAvatar";
import { ThemeProvider } from "../../hooks/ThemeProvider";
import {
  felixApi,
  FelixConfig,
  ConfigContent,
  ChatMessage,
  CopilotStreamController,
  CopilotStreamEvent,
} from "../../services/felixApi";

// Mock the felixApi module
vi.mock("../../services/felixApi", () => ({
  felixApi: {
    getGlobalConfig: vi.fn(),
    streamCopilotChat: vi.fn(),
  },
}));

// Mock window.confirm for happy-dom
const originalConfirm = window.confirm;
beforeAll(() => {
  window.confirm = vi.fn(() => true);
});
afterAll(() => {
  window.confirm = originalConfirm;
});

// Helper to render with ThemeProvider
const renderWithTheme = (ui: React.ReactElement) => {
  return render(<ThemeProvider defaultTheme="dark">{ui}</ThemeProvider>);
};

// Create a mock config object with copilot settings
const createMockConfig = (copilotEnabled: boolean = true): FelixConfig => ({
  version: "1.0.0",
  executor: {
    mode: "local",
    max_iterations: 10,
    default_mode: "planning",
    auto_transition: true,
  },
  agent: {
    executable: "droid",
    args: ["exec", "--"],
    working_directory: ".",
    environment: {},
  },
  paths: {
    specs: "specs",
    plan: "plan.md",
    agents: "AGENTS.md",
    runs: "runs",
  },
  backpressure: {
    enabled: true,
    commands: ["npm run lint", "npm test"],
    max_retries: 3,
  },
  ui: {},
  copilot: {
    enabled: copilotEnabled,
    provider: "openai",
    model: "gpt-4o",
    context_sources: {
      agents_md: true,
      learnings_md: true,
      prompt_md: true,
      requirements: true,
      other_specs: true,
    },
    features: {
      streaming: true,
      auto_suggest: true,
      context_aware: true,
    },
  },
});

const mockConfigResponse = (config: FelixConfig): ConfigContent => ({
  config,
  path: "\.felix/config.json",
});

// Helper to create a mock stream controller
const createMockStreamController = (): CopilotStreamController & {
  _triggerEvent: (event: CopilotStreamEvent) => void;
  _triggerError: (error: Error) => void;
  _triggerComplete: () => void;
} => {
  let eventCallback: ((event: CopilotStreamEvent) => void) | null = null;
  let errorCallback: ((error: Error) => void) | null = null;
  let completeCallback: (() => void) | null = null;

  return {
    onEvent: (callback) => {
      eventCallback = callback;
    },
    onError: (callback) => {
      errorCallback = callback;
    },
    onComplete: (callback) => {
      completeCallback = callback;
    },
    cancel: vi.fn(),
    _triggerEvent: (event) => eventCallback?.(event),
    _triggerError: (error) => errorCallback?.(error),
    _triggerComplete: () => completeCallback?.(),
  };
};

describe("CopilotChat Components", () => {
  const mockProjectId = "test-project-123";
  const mockOnInsertSpec = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
    // Default mock for global config
    vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
      mockConfigResponse(createMockConfig(true)),
    );
  });

  afterEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  describe("CopilotChatButton", () => {
    describe("Visibility", () => {
      it("renders when copilot is enabled", async () => {
        renderWithTheme(
          <CopilotChatButton isOpen={false} onClick={() => {}} />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });
      });

      it("does not render when copilot is disabled", async () => {
        vi.mocked(felixApi.getGlobalConfig).mockResolvedValue(
          mockConfigResponse(createMockConfig(false)),
        );

        renderWithTheme(
          <CopilotChatButton isOpen={false} onClick={() => {}} />,
        );

        // Wait for the async config check to complete
        await waitFor(() => {
          expect(felixApi.getGlobalConfig).toHaveBeenCalled();
        });

        // Button should not be in the document
        expect(
          screen.queryByRole("button", { name: /felix copilot chat/i }),
        ).not.toBeInTheDocument();
      });

      it("shows loading state and then renders button", async () => {
        let resolveConfig: (value: ConfigContent) => void;
        const configPromise = new Promise<ConfigContent>((resolve) => {
          resolveConfig = resolve;
        });
        vi.mocked(felixApi.getGlobalConfig).mockReturnValue(configPromise);

        renderWithTheme(
          <CopilotChatButton isOpen={false} onClick={() => {}} />,
        );

        // Button should not be visible during loading
        expect(
          screen.queryByRole("button", { name: /felix copilot chat/i }),
        ).not.toBeInTheDocument();

        // Resolve the config promise
        resolveConfig!(mockConfigResponse(createMockConfig(true)));

        // Now button should appear
        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });
      });
    });

    describe("Button Behavior", () => {
      it("calls onClick when clicked", async () => {
        const handleClick = vi.fn();

        renderWithTheme(
          <CopilotChatButton isOpen={false} onClick={handleClick} />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );
        expect(handleClick).toHaveBeenCalledTimes(1);
      });

      it("shows sparkle emoji", async () => {
        renderWithTheme(
          <CopilotChatButton isOpen={false} onClick={() => {}} />,
        );

        await waitFor(() => {
          expect(screen.getByText("✨")).toBeInTheDocument();
        });
      });

      it("changes aria-label when panel is open vs closed", async () => {
        const { rerender } = renderWithTheme(
          <CopilotChatButton isOpen={false} onClick={() => {}} />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /open felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        rerender(
          <ThemeProvider defaultTheme="dark">
            <CopilotChatButton isOpen={true} onClick={() => {}} />
          </ThemeProvider>,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /close felix copilot chat/i }),
          ).toBeInTheDocument();
        });
      });
    });

    describe("Unread Badge", () => {
      it("shows unread badge when unreadCount > 0 and panel is closed", async () => {
        renderWithTheme(
          <CopilotChatButton
            isOpen={false}
            onClick={() => {}}
            unreadCount={5}
          />,
        );

        await waitFor(() => {
          expect(screen.getByText("5")).toBeInTheDocument();
        });
      });

      it("does not show unread badge when panel is open", async () => {
        renderWithTheme(
          <CopilotChatButton
            isOpen={true}
            onClick={() => {}}
            unreadCount={5}
          />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        expect(screen.queryByText("5")).not.toBeInTheDocument();
      });

      it("shows 99+ for counts over 99", async () => {
        renderWithTheme(
          <CopilotChatButton
            isOpen={false}
            onClick={() => {}}
            unreadCount={150}
          />,
        );

        await waitFor(() => {
          expect(screen.getByText("99+")).toBeInTheDocument();
        });
      });

      it("does not show badge when unreadCount is 0", async () => {
        renderWithTheme(
          <CopilotChatButton
            isOpen={false}
            onClick={() => {}}
            unreadCount={0}
          />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        // No badge should be present
        expect(
          screen.queryByLabelText(/unread messages/i),
        ).not.toBeInTheDocument();
      });
    });
  });

  describe("CopilotChatPanel", () => {
    const defaultProps = {
      isOpen: true,
      onClose: vi.fn(),
      avatarState: "idle" as AvatarState,
      messages: [] as ChatMessage[],
      inputValue: "",
      onInputChange: vi.fn(),
      onSendMessage: vi.fn(),
      isStreaming: false,
      onCancelStream: vi.fn(),
      onClearHistory: vi.fn(),
      contextSourceCount: 4,
      onInsertSpec: vi.fn(),
      onQuickDraft: vi.fn(),
      onHelpCommand: vi.fn(),
    };

    describe("Panel Open/Close", () => {
      it("renders when isOpen is true", () => {
        renderWithTheme(<CopilotChatPanel {...defaultProps} isOpen={true} />);

        expect(
          screen.getByRole("dialog", { name: /felix copilot chat/i }),
        ).toBeInTheDocument();
        expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
      });

      it("has correct opacity when closed", () => {
        renderWithTheme(<CopilotChatPanel {...defaultProps} isOpen={false} />);

        const dialog = screen.getByRole("dialog", {
          name: /felix copilot chat/i,
        });
        expect(dialog).toHaveClass("opacity-0");
      });

      it("has correct opacity when open", () => {
        renderWithTheme(<CopilotChatPanel {...defaultProps} isOpen={true} />);

        const dialog = screen.getByRole("dialog", {
          name: /felix copilot chat/i,
        });
        expect(dialog).toHaveClass("opacity-100");
      });

      it("calls onClose when minimize button is clicked", () => {
        const handleClose = vi.fn();
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} onClose={handleClose} />,
        );

        fireEvent.click(screen.getByTitle("Minimize"));
        expect(handleClose).toHaveBeenCalledTimes(1);
      });

      it("calls onClose when ESC key is pressed", () => {
        const handleClose = vi.fn();
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} onClose={handleClose} />,
        );

        fireEvent.keyDown(document, { key: "Escape" });
        expect(handleClose).toHaveBeenCalledTimes(1);
      });
    });

    describe("Header", () => {
      it("shows Felix Copilot title", () => {
        renderWithTheme(<CopilotChatPanel {...defaultProps} />);

        expect(screen.getByText("Felix Copilot")).toBeInTheDocument();
      });

      it("shows context source count", () => {
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} contextSourceCount={4} />,
        );

        expect(screen.getByText("📚 4 sources")).toBeInTheDocument();
      });

      it("shows clear history button", () => {
        renderWithTheme(<CopilotChatPanel {...defaultProps} />);

        expect(screen.getByTitle("Clear history")).toBeInTheDocument();
      });
    });

    describe("Empty State", () => {
      it("shows empty state when no messages", () => {
        renderWithTheme(<CopilotChatPanel {...defaultProps} messages={[]} />);

        expect(screen.getByText("Hi! I'm Felix Copilot.")).toBeInTheDocument();
        expect(screen.getByText(/Ask me to draft a spec/)).toBeInTheDocument();
      });
    });

    describe("Message Rendering", () => {
      it("renders user messages aligned right with correct styling", () => {
        const messages: ChatMessage[] = [
          {
            id: "1",
            role: "user",
            content: "Hello copilot!",
            timestamp: new Date(),
          },
        ];

        renderWithTheme(
          <CopilotChatPanel {...defaultProps} messages={messages} />,
        );

        // User message should be present
        expect(screen.getByText("Hello copilot!")).toBeInTheDocument();

        // Check for user message bubble styling (bg-felix-500) - need to go up 2 levels
        // The text is in a div with whitespace-pre-wrap, its parent has bg-felix-500
        const messageText = screen.getByText("Hello copilot!");
        const messageBubble = messageText.parentElement;
        expect(messageBubble).toHaveClass("bg-felix-500");
      });

      it("renders assistant messages aligned left with markdown", () => {
        const messages: ChatMessage[] = [
          {
            id: "1",
            role: "assistant",
            content: "**Hello!** How can I help?",
            timestamp: new Date(),
          },
        ];

        renderWithTheme(
          <CopilotChatPanel {...defaultProps} messages={messages} />,
        );

        // Markdown should be rendered (bold text)
        expect(screen.getByText("Hello!")).toBeInTheDocument();
        expect(screen.getByText(/How can I help/)).toBeInTheDocument();
      });

      it("shows timestamps on messages", () => {
        const testDate = new Date("2026-01-28T10:30:00");
        const messages: ChatMessage[] = [
          {
            id: "1",
            role: "user",
            content: "Test message",
            timestamp: testDate,
          },
        ];

        renderWithTheme(
          <CopilotChatPanel {...defaultProps} messages={messages} />,
        );

        // Should show formatted time
        expect(screen.getByText(/10:30/)).toBeInTheDocument();
      });

      it("shows Insert Spec button for spec-like assistant messages", () => {
        // The looksLikeSpec function requires:
        // - At least one heading (^#+ .+)
        // - Content longer than 200 chars
        // - Multiple sections (2+ headings OR 2+ "- [" checklist items)
        const specContent = `# S-0001: Test Specification Title

## Narrative

As a user, I want to have a test specification that demonstrates the Insert Spec button functionality.
This narrative section provides additional context and explanation about what this specification covers.
It should be long enough to meet the 200 character minimum requirement.

## Acceptance Criteria

- [ ] First acceptance criterion that must be met
- [ ] Second acceptance criterion that must be verified
- [ ] Third acceptance criterion for completeness

## Technical Notes

Implementation details and technical considerations go here.`;

        const messages: ChatMessage[] = [
          {
            id: "1",
            role: "assistant",
            content: specContent,
            timestamp: new Date(),
          },
        ];

        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            messages={messages}
            isStreaming={false}
          />,
        );

        expect(screen.getByText("Insert Spec")).toBeInTheDocument();
      });

      it("calls onInsertSpec when Insert Spec button is clicked", () => {
        const handleInsertSpec = vi.fn();
        const specContent = `# S-0001: Test Specification

## Narrative

This is a test specification with enough content to be recognized as a spec.
The spec detection requires headings, substantial length, and multiple sections.

## Acceptance Criteria

- [ ] First criterion must be completed
- [ ] Second criterion must be verified`;

        const messages: ChatMessage[] = [
          {
            id: "1",
            role: "assistant",
            content: specContent,
            timestamp: new Date(),
          },
        ];

        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            messages={messages}
            onInsertSpec={handleInsertSpec}
            isStreaming={false}
          />,
        );

        fireEvent.click(screen.getByText("Insert Spec"));
        expect(handleInsertSpec).toHaveBeenCalledWith(specContent);
      });
    });

    describe("Input Area", () => {
      it("shows input placeholder", () => {
        renderWithTheme(<CopilotChatPanel {...defaultProps} />);

        expect(
          screen.getByPlaceholderText(/Ask me anything or type \/draft/),
        ).toBeInTheDocument();
      });

      it("updates input value on change", () => {
        const handleInputChange = vi.fn();
        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            onInputChange={handleInputChange}
          />,
        );

        const input = screen.getByPlaceholderText(/Ask me anything/);
        fireEvent.change(input, { target: { value: "Test message" } });

        expect(handleInputChange).toHaveBeenCalledWith("Test message");
      });

      it("calls onSendMessage when Enter is pressed", () => {
        const handleSendMessage = vi.fn();
        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            inputValue="Test"
            onSendMessage={handleSendMessage}
          />,
        );

        const input = screen.getByPlaceholderText(/Ask me anything/);
        fireEvent.keyDown(input, { key: "Enter", shiftKey: false });

        expect(handleSendMessage).toHaveBeenCalledTimes(1);
      });

      it("does not send on Shift+Enter (allows newline)", () => {
        const handleSendMessage = vi.fn();
        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            inputValue="Test"
            onSendMessage={handleSendMessage}
          />,
        );

        const input = screen.getByPlaceholderText(/Ask me anything/);
        fireEvent.keyDown(input, { key: "Enter", shiftKey: true });

        expect(handleSendMessage).not.toHaveBeenCalled();
      });

      it("disables send button when input is empty", () => {
        renderWithTheme(<CopilotChatPanel {...defaultProps} inputValue="" />);

        const sendButton = screen.getByTitle("Send");
        expect(sendButton).toBeDisabled();
      });

      it("enables send button when input has content", () => {
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} inputValue="Hello" />,
        );

        const sendButton = screen.getByTitle("Send");
        expect(sendButton).not.toBeDisabled();
      });

      it("shows character count when near limit", () => {
        const longText = "a".repeat(1850);
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} inputValue={longText} />,
        );

        expect(screen.getByText("1850/2000")).toBeInTheDocument();
      });

      it("disables send button when over character limit", () => {
        const tooLongText = "a".repeat(2001);
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} inputValue={tooLongText} />,
        );

        const sendButton = screen.getByTitle("Send");
        expect(sendButton).toBeDisabled();
      });
    });

    describe("Streaming State", () => {
      it("shows cancel button during streaming", () => {
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} isStreaming={true} />,
        );

        expect(screen.getByTitle("Cancel")).toBeInTheDocument();
      });

      it("calls onCancelStream when cancel button is clicked", () => {
        const handleCancelStream = vi.fn();
        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            isStreaming={true}
            onCancelStream={handleCancelStream}
          />,
        );

        fireEvent.click(screen.getByTitle("Cancel"));
        expect(handleCancelStream).toHaveBeenCalledTimes(1);
      });

      it("disables input during streaming", () => {
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} isStreaming={true} />,
        );

        const input = screen.getByPlaceholderText(/Ask me anything/);
        expect(input).toBeDisabled();
      });

      it("hides quick action buttons during streaming", () => {
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} isStreaming={true} />,
        );

        expect(screen.queryByText("Draft Spec")).not.toBeInTheDocument();
        expect(screen.queryByText("Help")).not.toBeInTheDocument();
      });
    });

    describe("Quick Actions", () => {
      it("shows Draft Spec button when not streaming", () => {
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} isStreaming={false} />,
        );

        expect(screen.getByText("Draft Spec")).toBeInTheDocument();
      });

      it("calls onQuickDraft when Draft Spec is clicked", () => {
        const handleQuickDraft = vi.fn();
        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            onQuickDraft={handleQuickDraft}
          />,
        );

        fireEvent.click(screen.getByText("Draft Spec"));
        expect(handleQuickDraft).toHaveBeenCalledTimes(1);
      });

      it("shows Help button when not streaming", () => {
        renderWithTheme(
          <CopilotChatPanel {...defaultProps} isStreaming={false} />,
        );

        expect(screen.getByText("Help")).toBeInTheDocument();
      });

      it("calls onHelpCommand when Help is clicked", () => {
        const handleHelpCommand = vi.fn();
        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            onHelpCommand={handleHelpCommand}
          />,
        );

        fireEvent.click(screen.getByText("Help"));
        expect(handleHelpCommand).toHaveBeenCalledTimes(1);
      });
    });

    describe("Clear History", () => {
      it("shows confirmation dialog when clear history is clicked", () => {
        const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);

        renderWithTheme(<CopilotChatPanel {...defaultProps} />);

        fireEvent.click(screen.getByTitle("Clear history"));

        expect(confirmSpy).toHaveBeenCalledWith(
          "Clear all conversation history?",
        );
        confirmSpy.mockRestore();
      });

      it("calls onClearHistory when confirmed", () => {
        const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(true);
        const handleClearHistory = vi.fn();

        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            onClearHistory={handleClearHistory}
          />,
        );

        fireEvent.click(screen.getByTitle("Clear history"));

        expect(handleClearHistory).toHaveBeenCalledTimes(1);
        confirmSpy.mockRestore();
      });

      it("does not call onClearHistory when cancelled", () => {
        const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);
        const handleClearHistory = vi.fn();

        renderWithTheme(
          <CopilotChatPanel
            {...defaultProps}
            onClearHistory={handleClearHistory}
          />,
        );

        fireEvent.click(screen.getByTitle("Clear history"));

        expect(handleClearHistory).not.toHaveBeenCalled();
        confirmSpy.mockRestore();
      });
    });
  });

  describe("CopilotAvatar", () => {
    it("renders with idle state by default", () => {
      renderWithTheme(<CopilotAvatar state="idle" />);

      const avatar = document.querySelector(".copilot-avatar");
      expect(avatar).toHaveClass("copilot-avatar-idle");
    });

    it("applies listening animation class", () => {
      renderWithTheme(<CopilotAvatar state="listening" />);

      const avatar = document.querySelector(".copilot-avatar");
      expect(avatar).toHaveClass("copilot-avatar-listening");
    });

    it("applies thinking animation class", () => {
      renderWithTheme(<CopilotAvatar state="thinking" />);

      const avatar = document.querySelector(".copilot-avatar");
      expect(avatar).toHaveClass("copilot-avatar-thinking");
    });

    it("applies speaking animation class", () => {
      renderWithTheme(<CopilotAvatar state="speaking" />);

      const avatar = document.querySelector(".copilot-avatar");
      expect(avatar).toHaveClass("copilot-avatar-speaking");
    });

    it("applies error animation class", () => {
      renderWithTheme(<CopilotAvatar state="error" />);

      const avatar = document.querySelector(".copilot-avatar");
      expect(avatar).toHaveClass("copilot-avatar-error");
    });

    it("renders at default size (48px)", () => {
      renderWithTheme(<CopilotAvatar state="idle" />);

      const avatar = document.querySelector(".copilot-avatar");
      expect(avatar).toHaveStyle({ width: "48px", height: "48px" });
    });

    it("renders at custom size", () => {
      renderWithTheme(<CopilotAvatar state="idle" size={64} />);

      const avatar = document.querySelector(".copilot-avatar");
      expect(avatar).toHaveStyle({ width: "64px", height: "64px" });
    });

    it("contains SVG element", () => {
      renderWithTheme(<CopilotAvatar state="idle" />);

      const svg = document.querySelector(".copilot-avatar svg");
      expect(svg).toBeInTheDocument();
    });
  });

  describe("CopilotChat (Integration)", () => {
    describe("localStorage Persistence", () => {
      it("loads chat history from localStorage on mount", async () => {
        const savedMessages: ChatMessage[] = [
          {
            id: "1",
            role: "user",
            content: "Previous message",
            timestamp: new Date("2026-01-27T10:00:00"),
          },
          {
            id: "2",
            role: "assistant",
            content: "Previous response",
            timestamp: new Date("2026-01-27T10:01:00"),
          },
        ];

        localStorage.setItem(
          `felix_copilot_chat_${mockProjectId}`,
          JSON.stringify(
            savedMessages.map((m) => ({
              ...m,
              timestamp: m.timestamp.toISOString(),
            })),
          ),
        );

        renderWithTheme(
          <CopilotChat
            projectId={mockProjectId}
            onInsertSpec={mockOnInsertSpec}
          />,
        );

        // Wait for config to load and component to render
        await waitFor(() => {
          expect(felixApi.getGlobalConfig).toHaveBeenCalled();
        });

        // Open the chat panel by clicking the button
        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        // Messages from localStorage should be displayed
        await waitFor(() => {
          expect(screen.getByText("Previous message")).toBeInTheDocument();
          expect(screen.getByText("Previous response")).toBeInTheDocument();
        });
      });

      it("saves chat history to localStorage when messages change", async () => {
        const mockStreamController = createMockStreamController();
        vi.mocked(felixApi.streamCopilotChat).mockReturnValue(
          mockStreamController,
        );

        renderWithTheme(
          <CopilotChat
            projectId={mockProjectId}
            onInsertSpec={mockOnInsertSpec}
          />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        // Open the panel
        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        await waitFor(() => {
          expect(
            screen.getByPlaceholderText(/Ask me anything/),
          ).toBeInTheDocument();
        });

        // Type and send a message
        const input = screen.getByPlaceholderText(/Ask me anything/);
        fireEvent.change(input, { target: { value: "Test message" } });
        fireEvent.click(screen.getByTitle("Send"));

        // Simulate response
        await act(async () => {
          mockStreamController._triggerEvent({ avatar_state: "speaking" });
          mockStreamController._triggerEvent({ token: "Hello!" });
          mockStreamController._triggerEvent({
            done: true,
            avatar_state: "idle",
          });
        });

        // Check localStorage
        await waitFor(() => {
          const saved = localStorage.getItem(
            `felix_copilot_chat_${mockProjectId}`,
          );
          expect(saved).toBeTruthy();
          const parsed = JSON.parse(saved!);
          expect(parsed.length).toBe(2); // User message + assistant message
        });
      });

      it("clears localStorage when clear history is called", async () => {
        // Pre-populate localStorage
        const savedMessages: ChatMessage[] = [
          {
            id: "1",
            role: "user",
            content: "Old message",
            timestamp: new Date(),
          },
        ];
        localStorage.setItem(
          `felix_copilot_chat_${mockProjectId}`,
          JSON.stringify(
            savedMessages.map((m) => ({
              ...m,
              timestamp: m.timestamp.toISOString(),
            })),
          ),
        );

        const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(true);

        renderWithTheme(
          <CopilotChat
            projectId={mockProjectId}
            onInsertSpec={mockOnInsertSpec}
          />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        // Open the panel
        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        await waitFor(() => {
          expect(screen.getByText("Old message")).toBeInTheDocument();
        });

        // Click clear history
        fireEvent.click(screen.getByTitle("Clear history"));

        await waitFor(() => {
          // Messages should be cleared (empty array saved, or null if removed)
          const saved = localStorage.getItem(
            `felix_copilot_chat_${mockProjectId}`,
          );
          // After clearing, either null or empty array is acceptable
          if (saved !== null) {
            const parsed = JSON.parse(saved);
            expect(parsed).toHaveLength(0);
          }
          // And the message should no longer be in the DOM
          expect(screen.queryByText("Old message")).not.toBeInTheDocument();
        });

        confirmSpy.mockRestore();
      });

      it("maintains separate history for different projects", async () => {
        const projectAMessages = [
          {
            id: "1",
            role: "user" as const,
            content: "Project A message",
            timestamp: new Date().toISOString(),
          },
        ];
        const projectBMessages = [
          {
            id: "2",
            role: "user" as const,
            content: "Project B message",
            timestamp: new Date().toISOString(),
          },
        ];

        localStorage.setItem(
          "felix_copilot_chat_project-a",
          JSON.stringify(projectAMessages),
        );
        localStorage.setItem(
          "felix_copilot_chat_project-b",
          JSON.stringify(projectBMessages),
        );

        // Render with project-a
        const { rerender } = renderWithTheme(
          <CopilotChat projectId="project-a" onInsertSpec={mockOnInsertSpec} />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        await waitFor(() => {
          expect(screen.getByText("Project A message")).toBeInTheDocument();
          expect(
            screen.queryByText("Project B message"),
          ).not.toBeInTheDocument();
        });
      });

      it("limits stored messages to 50 (FIFO) when new message is added", async () => {
        // Create 49 messages (so adding 2 more will trigger the trim to 50)
        const initialMessages = Array.from({ length: 49 }, (_, i) => ({
          id: `msg-${i}`,
          role: (i % 2 === 0 ? "user" : "assistant") as "user" | "assistant",
          content: `Message ${i}`,
          timestamp: new Date().toISOString(),
        }));

        localStorage.setItem(
          `felix_copilot_chat_${mockProjectId}`,
          JSON.stringify(initialMessages),
        );

        const mockStreamController = createMockStreamController();
        vi.mocked(felixApi.streamCopilotChat).mockReturnValue(
          mockStreamController,
        );

        renderWithTheme(
          <CopilotChat
            projectId={mockProjectId}
            onInsertSpec={mockOnInsertSpec}
          />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        // Open panel
        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        await waitFor(() => {
          expect(
            screen.getByPlaceholderText(/Ask me anything/),
          ).toBeInTheDocument();
        });

        // Send a new message (this will add 2 messages: user + assistant)
        const input = screen.getByPlaceholderText(/Ask me anything/);
        fireEvent.change(input, { target: { value: "New message" } });
        fireEvent.click(screen.getByTitle("Send"));

        // Simulate response
        await act(async () => {
          mockStreamController._triggerEvent({ avatar_state: "speaking" });
          mockStreamController._triggerEvent({ token: "Response" });
          mockStreamController._triggerEvent({
            done: true,
            avatar_state: "idle",
          });
        });

        // Now check localStorage - should be trimmed to 50
        await waitFor(() => {
          const saved = localStorage.getItem(
            `felix_copilot_chat_${mockProjectId}`,
          );
          expect(saved).toBeTruthy();
          const parsed = JSON.parse(saved!);
          expect(parsed.length).toBeLessThanOrEqual(50);
        });
      });
    });

    describe("Panel Toggle", () => {
      it("opens panel when button is clicked", async () => {
        renderWithTheme(
          <CopilotChat
            projectId={mockProjectId}
            onInsertSpec={mockOnInsertSpec}
          />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        // Panel should not be visible initially
        expect(
          screen.queryByRole("dialog", { name: /felix copilot chat/i }),
        ).toHaveClass("opacity-0");

        // Click button to open
        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        // Panel should now be visible
        await waitFor(() => {
          expect(
            screen.getByRole("dialog", { name: /felix copilot chat/i }),
          ).toHaveClass("opacity-100");
        });
      });

      it("closes panel when button is clicked again", async () => {
        renderWithTheme(
          <CopilotChat
            projectId={mockProjectId}
            onInsertSpec={mockOnInsertSpec}
          />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        // Open panel
        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        await waitFor(() => {
          expect(
            screen.getByRole("dialog", { name: /felix copilot chat/i }),
          ).toHaveClass("opacity-100");
        });

        // Click button again to close
        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        await waitFor(() => {
          expect(
            screen.getByRole("dialog", { name: /felix copilot chat/i }),
          ).toHaveClass("opacity-0");
        });
      });
    });

    describe("Quick Draft Action", () => {
      it('sets input to "Draft a spec for: " when Quick Draft is clicked', async () => {
        renderWithTheme(
          <CopilotChat
            projectId={mockProjectId}
            onInsertSpec={mockOnInsertSpec}
          />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        // Open panel
        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        await waitFor(() => {
          expect(screen.getByText("Draft Spec")).toBeInTheDocument();
        });

        // Click Draft Spec
        fireEvent.click(screen.getByText("Draft Spec"));

        // Input should have the draft prompt
        const input = screen.getByPlaceholderText(
          /Ask me anything/,
        ) as HTMLTextAreaElement;
        expect(input.value).toBe("Draft a spec for: ");
      });
    });

    describe("Help Command", () => {
      it("shows help message when Help is clicked", async () => {
        renderWithTheme(
          <CopilotChat
            projectId={mockProjectId}
            onInsertSpec={mockOnInsertSpec}
          />,
        );

        await waitFor(() => {
          expect(
            screen.getByRole("button", { name: /felix copilot chat/i }),
          ).toBeInTheDocument();
        });

        // Open panel
        fireEvent.click(
          screen.getByRole("button", { name: /felix copilot chat/i }),
        );

        await waitFor(() => {
          expect(screen.getByText("Help")).toBeInTheDocument();
        });

        // Click Help
        fireEvent.click(screen.getByText("Help"));

        // Help message should appear
        await waitFor(() => {
          expect(screen.getByText(/Available Commands/)).toBeInTheDocument();
        });
      });
    });
  });
});

