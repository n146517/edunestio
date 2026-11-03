import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  ApiResponse,
  ItemsData,
  LeaveApplyRequest,
  LeaveDecisionRequest,
  LeaveRequest
} from '../models/api.models';

/** Typed client for the Leave module. Unwraps the ApiResponse envelope. */
@Injectable({ providedIn: 'root' })
export class LeaveService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/leave`;

  apply(body: LeaveApplyRequest): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(this.base, body);
  }

  mine(): Observable<LeaveRequest[]> {
    return this.http
      .get<ApiResponse<ItemsData<LeaveRequest>>>(`${this.base}/mine`)
      .pipe(map((r) => r.data?.items ?? []));
  }

  list(q: { status?: string; classId?: number; search?: string } = {}): Observable<LeaveRequest[]> {
    let p = new HttpParams();
    if (q.status) p = p.set('status', q.status);
    if (q.classId) p = p.set('classId', q.classId);
    if (q.search) p = p.set('search', q.search);
    return this.http
      .get<ApiResponse<ItemsData<LeaveRequest>>>(this.base, { params: p })
      .pipe(map((r) => r.data?.items ?? []));
  }

  cancel(leaveId: number): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/${leaveId}/cancel`, {});
  }

  decide(leaveId: number, body: LeaveDecisionRequest): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/${leaveId}/decide`, body);
  }
}
