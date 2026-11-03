import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map, tap } from 'rxjs';
import { environment } from '../../../environments/environment';
import { ApiResponse, CurrentUser, LoginRequest, LoginResult } from '../models/api.models';
import { AuthStore } from './auth.store';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly store = inject(AuthStore);
  private readonly baseUrl = `${environment.apiBaseUrl}/auth`;

  login(request: LoginRequest): Observable<LoginResult> {
    return this.http.post<ApiResponse<LoginResult>>(`${this.baseUrl}/login`, request).pipe(
      map((res) => {
        if (!res.isSuccess || !res.data) {
          throw new Error(res.resultCodeDescription ?? 'Login failed');
        }
        return res.data;
      }),
      tap((result) => this.store.set(result))
    );
  }

  me(): Observable<CurrentUser | null> {
    return this.http
      .get<ApiResponse<CurrentUser>>(`${this.baseUrl}/me`)
      .pipe(map((res) => res.data));
  }

  logout(): void {
    this.store.clear();
  }
}
