import { Injectable, computed, signal } from '@angular/core';
import { LoginResult } from '../models/api.models';

const STORAGE_KEY = 'edunestio.auth';

/**
 * Holds authentication state as signals. The opaque bearer token is kept in memory
 * and mirrored to sessionStorage (tab-scoped) so a reload during development does
 * not force a re-login. The route guard/state is a UX convenience only; the API
 * enforces all real authorization server-side.
 */
@Injectable({ providedIn: 'root' })
export class AuthStore {
  private readonly _auth = signal<LoginResult | null>(this.restore());

  readonly isAuthenticated = computed(() => {
    const a = this._auth();
    return !!a && new Date(a.expiresAtUtc).getTime() > Date.now();
  });

  readonly username = computed(() => this._auth()?.username ?? null);
  readonly fullName = computed(() => this._auth()?.fullName ?? null);
  /** The student id this login represents (Student/Guardian self-service), or null. */
  readonly studentId = computed(() => this._auth()?.studentId ?? null);
  readonly tenantId = computed(() => this._auth()?.tenantId ?? null);
  readonly tenantName = computed(() => this._auth()?.tenantName ?? null);
  readonly roles = computed(() => this._auth()?.roles ?? []);
  readonly permissions = computed(() => this._auth()?.permissions ?? []);

  /**
   * True when the signed-in user is a student or guardian. These are self-service
   * roles that should only see read-only information, never administrative actions
   * like changing status, deactivating or promoting a student.
   */
  readonly isStudentOrGuardian = computed(() => {
    const r = this._auth()?.roles ?? [];
    return r.includes('Student') || r.includes('Guardian');
  });

  get token(): string | null {
    return this._auth()?.token ?? null;
  }

  hasPermission(permission: string): boolean {
    const a = this._auth();
    if (!a) return false;
    return a.roles.includes('SaaSSuperAdmin') || a.permissions.includes(permission);
  }

  hasRole(role: string): boolean {
    return (this._auth()?.roles ?? []).includes(role);
  }

  set(result: LoginResult): void {
    this._auth.set(result);
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(result));
  }

  clear(): void {
    this._auth.set(null);
    sessionStorage.removeItem(STORAGE_KEY);
  }

  private restore(): LoginResult | null {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    try {
      return JSON.parse(raw) as LoginResult;
    } catch {
      sessionStorage.removeItem(STORAGE_KEY);
      return null;
    }
  }
}
