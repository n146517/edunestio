import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import { ApiResponse, EnquiryPage, EnquiryUpsert, Followup, ItemsData } from '../models/api.models';

/** Typed client for the Admissions & Enquiry CRM module. */
@Injectable({ providedIn: 'root' })
export class AdmissionService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/admissions`;

  listEnquiries(params: { search?: string; stage?: string; page?: number; pageSize?: number }): Observable<EnquiryPage | null> {
    let p = new HttpParams().set('page', params.page ?? 1).set('pageSize', params.pageSize ?? 20);
    if (params.search) p = p.set('search', params.search);
    if (params.stage) p = p.set('stage', params.stage);
    return this.http.get<ApiResponse<EnquiryPage>>(`${this.base}/enquiries`, { params: p }).pipe(map((r) => r.data));
  }

  saveEnquiry(body: EnquiryUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/enquiries`, body);
  }

  listFollowups(enquiryId: number): Observable<Followup[]> {
    return this.http.get<ApiResponse<ItemsData<Followup>>>(`${this.base}/enquiries/${enquiryId}/followups`).pipe(map((r) => r.data?.items ?? []));
  }

  addFollowup(enquiryId: number, body: { Note: string; Outcome?: string | null; Stage?: string | null }): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/enquiries/${enquiryId}/followups`, body);
  }

  convert(enquiryId: number, body: { FirstName?: string | null; LastName?: string | null } = {}): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/enquiries/${enquiryId}/convert`, body);
  }
}
