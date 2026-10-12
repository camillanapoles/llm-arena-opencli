/**
 * Pluggable HTTP transport for the GitHub Actions driver.
 *
 * Tests inject a mock; production uses fetch against api.github.com. Keeping
 * the transport injectable is what makes the driver hermetic in CI.
 */

export interface TransportRequest {
  method: string;
  url: string;
  headers: Record<string, string>;
  body?: string | undefined;
}

export interface TransportResponse {
  status: number;
  body: string;
}

export interface ActionsTransport {
  request(req: TransportRequest): Promise<TransportResponse>;
}

export class FetchTransport implements ActionsTransport {
  async request(req: TransportRequest): Promise<TransportResponse> {
    const response = await fetch(req.url, {
      method: req.method,
      headers: req.headers,
      body: req.body,
    });
    return { status: response.status, body: await response.text() };
  }
}

/** In-memory transport used by tests and dry-run mode. */
export class MockTransport implements ActionsTransport {
  readonly requests: TransportRequest[] = [];
  private readonly responder: (req: TransportRequest) => TransportResponse;

  constructor(responder?: (req: TransportRequest) => TransportResponse) {
    this.responder = responder ?? (() => ({ status: 204, body: "" }));
  }

  async request(req: TransportRequest): Promise<TransportResponse> {
    this.requests.push(req);
    return this.responder(req);
  }
}
