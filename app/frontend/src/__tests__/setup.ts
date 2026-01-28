import '@testing-library/jest-dom';
import { vi } from 'vitest';

// Mock window.matchMedia for tests
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation(query => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});

// Mock ResizeObserver
global.ResizeObserver = vi.fn().mockImplementation(() => ({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
}));

// Mock WebSocket to prevent actual network connections during tests
// This avoids the Node.js internal assertion error when WebSocket tries to connect
class MockWebSocket {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSING = 2;
  static CLOSED = 3;

  url: string;
  readyState: number = MockWebSocket.CONNECTING;
  onopen: ((event: Event) => void) | null = null;
  onmessage: ((event: MessageEvent) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  onclose: ((event: CloseEvent) => void) | null = null;

  constructor(url: string) {
    this.url = url;
    // Simulate connection close immediately to prevent hanging connections
    setTimeout(() => {
      this.readyState = MockWebSocket.CLOSED;
      if (this.onclose) {
        this.onclose({ code: 1006, reason: '', wasClean: false } as CloseEvent);
      }
    }, 0);
  }

  send(_data: string | ArrayBuffer | Blob | ArrayBufferView): void {
    // Mock send - do nothing
  }

  close(_code?: number, _reason?: string): void {
    this.readyState = MockWebSocket.CLOSED;
  }

  addEventListener(_type: string, _listener: EventListener): void {
    // Mock addEventListener - do nothing
  }

  removeEventListener(_type: string, _listener: EventListener): void {
    // Mock removeEventListener - do nothing
  }
}

// @ts-expect-error - WebSocket mock for testing
global.WebSocket = MockWebSocket;
