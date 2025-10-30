/**
 * Chat System API Client
 *
 * Service Strategy:
 * - Rails API (port 3000): Full CRUD support
 * - Go Service (port 8080): High-performance writes ONLY (create chat, create message)
 *
 * Implementation:
 * - ALL read operations (GET) → Always use Rails
 * - Create Chat → Uses selected service (Rails or Go)
 * - Create Message → Uses selected service (Rails or Go)
 * - Create/List Applications → Always uses Rails (Go doesn't support)
 * - List Chats/Messages → Always uses Rails (Go doesn't support)
 * - Search → Always uses Rails (Go doesn't support)
 */

export type ServiceType = 'rails' | 'go';

const BASE_URLS = {
  rails: import.meta.env.VITE_RAILS_API_URL || 'http://localhost:3000/api/v1',
  go: import.meta.env.VITE_GO_API_URL || 'http://localhost:8080/api/v1',
};

export interface PerformanceMetric {
  endpoint: string;
  service: ServiceType;
  duration: number;
  timestamp: number;
}

export interface ChatApplication {
  name: string;
  token: string;
  chats_count: number;
}

export interface Chat {
  number: number;
  messages_count: number;
}

export interface Message {
  number: number;
  body: string;
}

export interface ApiError {
  error?: string;
  errors?: Record<string, string[]>;
}

class ApiClient {
  private async handleResponse<T>(response: Response): Promise<T> {
    if (!response.ok) {
      const errorData: ApiError = await response.json().catch(() => ({}));

      // Handle validation errors (422)
      if (response.status === 422 && errorData.errors) {
        const messages = Object.entries(errorData.errors)
          .map(([field, errors]) => `${field}: ${errors.join(', ')}`)
          .join('; ');
        throw new Error(messages);
      }

      // Handle other errors (404, 400, etc.)
      if (errorData.error) {
        throw new Error(errorData.error);
      }

      // Fallback error message
      throw new Error(`Request failed with status ${response.status}`);
    }

    return response.json();
  }
  async measureRequest<T>(
    service: ServiceType,
    endpoint: string,
    request: () => Promise<T>
  ): Promise<{ data: T; metric: PerformanceMetric }> {
    const startTime = performance.now();
    const data = await request();
    const endTime = performance.now();
    const duration = endTime - startTime;

    const metric: PerformanceMetric = {
      endpoint,
      service,
      duration,
      timestamp: Date.now(),
    };

    return { data, metric };
  }

  // Chat Applications
  async createApplication(
    service: ServiceType,
    name: string
  ): Promise<{ data: ChatApplication; metric: PerformanceMetric }> {
    // Always use Rails for application operations (Go doesn't support this)
    return this.measureRequest('rails', 'create_application', async () => {
      const response = await fetch(`${BASE_URLS.rails}/chat_applications`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_application: { name } }),
      });
      return this.handleResponse<ChatApplication>(response);
    });
  }

  async listApplications(
    service: ServiceType
  ): Promise<{ data: ChatApplication[]; metric: PerformanceMetric }> {
    // Always use Rails for read operations (Go doesn't support reads)
    return this.measureRequest('rails', 'list_applications', async () => {
      const response = await fetch(`${BASE_URLS.rails}/chat_applications`);
      return this.handleResponse<ChatApplication[]>(response);
    });
  }

  // Chats
  async createChat(
    service: ServiceType,
    token: string
  ): Promise<{ data: Chat; metric: PerformanceMetric }> {
    return this.measureRequest(service, 'create_chat', async () => {
      const response = await fetch(
        `${BASE_URLS[service]}/chat_applications/${token}/chats`,
        { method: 'POST' }
      );
      return this.handleResponse<Chat>(response);
    });
  }

  async listChats(
    service: ServiceType,
    token: string
  ): Promise<{ data: Chat[]; metric: PerformanceMetric }> {
    // Always use Rails for read operations (Go doesn't support reads)
    return this.measureRequest('rails', 'list_chats', async () => {
      const response = await fetch(
        `${BASE_URLS.rails}/chat_applications/${token}/chats`
      );
      return this.handleResponse<Chat[]>(response);
    });
  }

  // Messages
  async createMessage(
    service: ServiceType,
    token: string,
    chatNumber: number,
    body: string
  ): Promise<{ data: Message; metric: PerformanceMetric }> {
    return this.measureRequest(service, 'create_message', async () => {
      const response = await fetch(
        `${BASE_URLS[service]}/chat_applications/${token}/chats/${chatNumber}/messages`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: { body } }),
        }
      );
      return this.handleResponse<Message>(response);
    });
  }

  async listMessages(
    service: ServiceType,
    token: string,
    chatNumber: number
  ): Promise<{ data: Message[]; metric: PerformanceMetric }> {
    // Always use Rails for read operations (Go doesn't support reads)
    return this.measureRequest('rails', 'list_messages', async () => {
      const response = await fetch(
        `${BASE_URLS.rails}/chat_applications/${token}/chats/${chatNumber}/messages`
      );
      return this.handleResponse<Message[]>(response);
    });
  }

  async searchMessages(
    service: ServiceType,
    token: string,
    chatNumber: number,
    query: string
  ): Promise<{ data: Message[]; metric: PerformanceMetric }> {
    // Always use Rails for read operations (Go doesn't support reads)
    return this.measureRequest('rails', 'search_messages', async () => {
      const response = await fetch(
        `${BASE_URLS.rails}/chat_applications/${token}/chats/${chatNumber}/messages/search?q=${encodeURIComponent(query)}`
      );
      return this.handleResponse<Message[]>(response);
    });
  }
}

export const api = new ApiClient();
