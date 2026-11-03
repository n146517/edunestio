import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import { ApiResponse, TenantSettings } from '../models/api.models';

/** Per-school settings (attendance mode, etc.). */
@Injectable({ providedIn: 'root' })
export class SettingsService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/settings`;

  get(): Observable<TenantSettings | null> {
    return this.http.get<ApiResponse<TenantSettings>>(this.base).pipe(map((r) => r.data));
  }

  setAttendanceMode(mode: 'Daily' | 'Subject'): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(this.base, { AttendanceMode: mode });
  }
}
