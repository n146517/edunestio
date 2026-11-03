import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  ApiResponse, ItemsData, FeeHead, FeeHeadUpsert, FeeLedger, FeeAssignRequest,
  PaymentRequest, Defaulter, CollectionReport
} from '../models/api.models';

/** Typed client for the Fees & Finance module. */
@Injectable({ providedIn: 'root' })
export class FeeService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/fees`;

  listHeads(): Observable<FeeHead[]> {
    return this.http.get<ApiResponse<ItemsData<FeeHead>>>(`${this.base}/heads`).pipe(map((r) => r.data?.items ?? []));
  }
  saveHead(body: FeeHeadUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/heads`, body);
  }

  assign(body: FeeAssignRequest): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/assign`, body);
  }
  ledger(studentId: number): Observable<FeeLedger | null> {
    return this.http.get<ApiResponse<FeeLedger>>(`${this.base}/ledger/${studentId}`).pipe(map((r) => r.data));
  }
  pay(body: PaymentRequest): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/payments`, body);
  }

  defaulters(classId?: number): Observable<Defaulter[]> {
    let p = new HttpParams();
    if (classId) p = p.set('classId', classId);
    return this.http.get<ApiResponse<ItemsData<Defaulter>>>(`${this.base}/defaulters`, { params: p }).pipe(map((r) => r.data?.items ?? []));
  }
  collection(from?: string, to?: string): Observable<CollectionReport | null> {
    let p = new HttpParams();
    if (from) p = p.set('from', from);
    if (to) p = p.set('to', to);
    return this.http.get<ApiResponse<CollectionReport>>(`${this.base}/collection`, { params: p }).pipe(map((r) => r.data));
  }
}
