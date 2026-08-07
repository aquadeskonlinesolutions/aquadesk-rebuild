# AquaDesk — Live App Real Schema Snapshot

Pulled 2026-08-07 by the user directly from the **live** Supabase project's
SQL editor (read-only `information_schema`/`pg_constraint` queries — no
data, no credentials, nothing that touches the never-connect-to-live rule).
This is the actual, ground-truth live schema — supersedes any assumption
made in `LIVE_DATA_MIGRATION_MAPPING.md` that was inferred only from
reading the old app's JS. Where the two disagree, **this file wins**.

Queries used (for reference, re-run any time a refresh is needed):
```sql
-- public schema, every table/column
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;

-- auth schema, users/identities only
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'auth' and table_name in ('users', 'identities')
order by table_name, ordinal_position;

-- every check constraint in public
select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where connamespace = 'public'::regnamespace and contype = 'c'
order by conname;
```

---

## `public` schema — every table/column

```
table_name,column_name,data_type,is_nullable,column_default
activities,created_at,timestamp with time zone,NO,now()
activities,dive_center_id,uuid,YES,gen_random_uuid()
activities,diver_id,uuid,YES,gen_random_uuid()
activities,date,date,YES,null
activities,dive_site,text,YES,null
activities,staff_id,uuid,YES,gen_random_uuid()
activities,dive_rate,numeric,YES,null
activities,fuel_surcharge,numeric,YES,null
activities,marine_tax,numeric,YES,null
activities,nitrox_fee,numeric,YES,null
activities,equipment_rental,numeric,YES,null
activities,addons,numeric,YES,null
activities,discount,numeric,YES,null
activities,total,numeric,YES,null
activities,status,text,YES,null
activities,notes,text,YES,null
activities,schedule_id,uuid,YES,null
activities,id,uuid,NO,gen_random_uuid()
activities,visit_id,uuid,YES,gen_random_uuid()
activities,staff_name,text,YES,null
activities,shark_fee,numeric,YES,0
activities,fee_15l,numeric,YES,0
activities,fifteen_l_fee,numeric,YES,0
activities,addon_breakdown,jsonb,YES,null
activities,equipment_breakdown,jsonb,YES,null
activity_rates,created_at,timestamp with time zone,NO,now()
activity_rates,dive_center_id,uuid,YES,gen_random_uuid()
activity_rates,activity_name,text,YES,null
activity_rates,category,text,YES,null
activity_rates,base_rate,numeric,YES,null
activity_rates,fuel_surcharge,numeric,YES,null
activity_rates,marine_tax,numeric,YES,null
activity_rates,nitrox_fee,numeric,YES,null
activity_rates,equipment_rental,numeric,YES,null
activity_rates,is_active,boolean,YES,null
activity_rates,id,uuid,NO,gen_random_uuid()
audit_logs,id,uuid,NO,gen_random_uuid()
audit_logs,dive_center_id,uuid,NO,null
audit_logs,action,text,NO,null
audit_logs,performed_by,uuid,NO,null
audit_logs,target_type,text,NO,null
audit_logs,target_id,uuid,NO,null
audit_logs,notes,text,YES,null
audit_logs,created_at,timestamp with time zone,NO,now()
billing_payments,id,uuid,NO,gen_random_uuid()
billing_payments,dive_center_id,uuid,NO,null
billing_payments,amount,numeric,NO,null
billing_payments,paid_on,date,NO,CURRENT_DATE
billing_payments,recorded_by,uuid,YES,null
billing_payments,notes,text,YES,null
billing_payments,created_at,timestamp with time zone,NO,now()
boats,created_at,timestamp with time zone,NO,now()
boats,dive_center_id,uuid,YES,gen_random_uuid()
boats,name,text,YES,null
boats,type,text,YES,null
boats,capacity,smallint,YES,null
boats,is_active,boolean,YES,null
boats,id,uuid,NO,gen_random_uuid()
boats,captain,text,YES,null
boats,boat_type,text,YES,null
boats,fuel_type,text,YES,null
course_rates,created_at,timestamp with time zone,NO,now()
course_rates,dive_center_id,uuid,YES,gen_random_uuid()
course_rates,course_name,text,YES,null
course_rates,price,numeric,YES,null
course_rates,is_active,boolean,YES,null
course_rates,id,uuid,NO,gen_random_uuid()
deposits,id,uuid,NO,gen_random_uuid()
deposits,dive_center_id,uuid,NO,null
deposits,visit_id,uuid,NO,null
deposits,diver_id,uuid,NO,null
deposits,amount,numeric,NO,null
deposits,method,text,NO,'cash'::text
deposits,deposit_date,date,NO,null
deposits,received_by,text,NO,null
deposits,recorded_by_user_id,uuid,YES,null
deposits,created_at,timestamp with time zone,YES,now()
dive_centers,created_at,timestamp with time zone,NO,now()
dive_centers,name,text,YES,null
dive_centers,email,text,YES,null
dive_centers,phone,text,YES,null
dive_centers,address,text,YES,null
dive_centers,logo_url,text,YES,null
dive_centers,billing_password,text,YES,null
dive_centers,subscription_status,text,YES,'active'::text
dive_centers,id,uuid,NO,gen_random_uuid()
dive_centers,pricing_mode,text,YES,null
dive_centers,owner_password,text,YES,null
dive_centers,fuel_current_level,numeric,YES,0
dive_centers,fuel_low_threshold,numeric,YES,0
dive_centers,waiver_pdf_url,text,YES,null
dive_centers,waiver_text,text,YES,null
dive_centers,waiver_updated_at,timestamp with time zone,YES,null
dive_centers,fuel_gasoline_level,numeric,YES,0
dive_centers,fuel_gasoline_threshold,numeric,YES,20
dive_centers,fuel_gasoline_last_reset_at,timestamp with time zone,YES,null
dive_centers,fuel_diesel_level,numeric,YES,0
dive_centers,fuel_diesel_threshold,numeric,YES,50
dive_centers,fuel_diesel_last_reset_at,timestamp with time zone,YES,null
dive_centers,staff_token,text,YES,null
dive_centers,staff_token_date,date,YES,null
dive_centers,waiver_content,text,YES,null
dive_centers,waiver_content_updated_by,uuid,YES,null
dive_centers,billing_due_date,date,YES,null
dive_centers,last_payment_date,date,YES,null
dive_centers,billing_amount,numeric,NO,4000
dive_centers,billing_cycle,text,NO,'monthly'::text
dive_centers,offers_dive_insurance,boolean,YES,false
dive_centers,insurance_referral_link,text,YES,null
dive_sites,created_at,timestamp with time zone,NO,now()
dive_sites,dive_center_id,uuid,YES,gen_random_uuid()
dive_sites,site_name,text,YES,null
dive_sites,distance,text,YES,null
dive_sites,fuel_estimate,text,YES,null
dive_sites,linked_package_id,uuid,YES,gen_random_uuid()
dive_sites,is_active,boolean,YES,null
dive_sites,id,uuid,NO,gen_random_uuid()
dive_sites,shark_fee,boolean,YES,false
diver_equipment,created_at,timestamp with time zone,NO,now()
diver_equipment,dive_center_id,uuid,YES,gen_random_uuid()
diver_equipment,diver_id,uuid,YES,gen_random_uuid()
diver_equipment,equipment_id,uuid,YES,gen_random_uuid()
diver_equipment,assigned_date,date,YES,null
diver_equipment,returned_date,date,YES,null
diver_equipment,condition_out,text,YES,null
diver_equipment,condition_in,text,YES,null
diver_equipment,notes,text,YES,null
diver_equipment,id,uuid,NO,gen_random_uuid()
diver_notes,id,uuid,NO,gen_random_uuid()
diver_notes,dive_center_id,uuid,NO,null
diver_notes,diver_id,uuid,NO,null
diver_notes,author_user_id,uuid,YES,null
diver_notes,author_name,text,NO,null
diver_notes,note,text,NO,null
diver_notes,created_at,timestamp with time zone,NO,now()
diver_registrations,id,uuid,NO,gen_random_uuid()
diver_registrations,diver_id,uuid,NO,null
diver_registrations,dive_center_id,uuid,NO,null
diver_registrations,waiver_signed,boolean,YES,null
diver_registrations,waiver_date,date,YES,null
diver_registrations,waiver_signature_url,text,YES,null
diver_registrations,waiver_content_snapshot,text,YES,null
diver_registrations,medical_flag,boolean,YES,null
diver_registrations,medical_answers,jsonb,YES,null
diver_registrations,medical_answers_snapshot,jsonb,YES,null
diver_registrations,privacy_notice_snapshot,text,YES,null
diver_registrations,privacy_consent_at,timestamp with time zone,YES,null
diver_registrations,arrival_date,date,YES,null
diver_registrations,departure_date,date,YES,null
diver_registrations,certification_level,text,YES,null
diver_registrations,equipment_requested,text,YES,null
diver_registrations,group_id,uuid,YES,null
diver_registrations,needs_equipment,boolean,YES,null
diver_registrations,equipment_preference,text,YES,null
diver_registrations,created_at,timestamp with time zone,NO,now()
diver_staff_defaults,id,uuid,NO,gen_random_uuid()
diver_staff_defaults,dive_center_id,uuid,NO,null
diver_staff_defaults,diver_id,uuid,NO,null
diver_staff_defaults,staff_id,uuid,NO,null
diver_staff_defaults,updated_at,timestamp with time zone,NO,now()
divers,created_at,timestamp with time zone,NO,now()
divers,dive_center_id,uuid,YES,gen_random_uuid()
divers,first_name,text,YES,null
divers,last_name,text,YES,null
divers,email,text,YES,null
divers,phone,text,YES,null
divers,whatsapp,text,YES,null
divers,birthday,date,YES,null
divers,age,smallint,YES,null
divers,nationality,text,YES,null
divers,emergency_contact_name,text,YES,null
divers,emergency_contact_phone,text,YES,null
divers,emergency_contact_email,text,YES,null
divers,emergency_contact_relationship,text,YES,null
divers,certification_level,text,YES,null
divers,training_agency,text,YES,null
divers,logged_dives,smallint,YES,null
divers,last_dive_date,date,YES,null
divers,nitrox_certified,boolean,YES,null
divers,waiver_signed,boolean,YES,null
divers,waiver_date,date,YES,null
divers,waiver_signature_url,text,YES,null
divers,notes,text,YES,null
divers,needs_equipment,boolean,YES,null
divers,equipment_preference,text,YES,null
divers,equipment notes,text,YES,null
divers,id,uuid,NO,gen_random_uuid()
divers,group_id,uuid,YES,null
divers,arrival_date,date,YES,null
divers,departure_date,date,YES,null
divers,accommodation,text,YES,null
divers,food_allergies,text,YES,null
divers,equipment_requested,text,YES,null
divers,is_minor,boolean,YES,false
divers,medical_flag,boolean,YES,false
divers,duplicate_email_flag,boolean,YES,false
divers,waiver_opened,boolean,YES,false
divers,medical_answers,jsonb,YES,null
divers,medical_acknowledged_at,timestamp with time zone,YES,null
divers,medical_acknowledged_by,uuid,YES,null
divers,medical_acknowledged,boolean,YES,false
divers,privacy_notice_id,uuid,YES,null
divers,privacy_notice_snapshot,text,YES,null
divers,privacy_consent_at,timestamp with time zone,YES,null
divers,waiver_content_snapshot,text,YES,null
divers,medical_answers_snapshot,jsonb,YES,null
divers,cert_card_url,text,YES,null
divers,has_dive_insurance,boolean,YES,null
divers,insurance_provider,text,YES,null
divers,insurance_policy_number,text,YES,null
divers,wants_insurance_referral,boolean,YES,null
equipment,created_at,timestamp with time zone,NO,now()
equipment,dive_center_id,uuid,YES,gen_random_uuid()
equipment,name,text,YES,null
equipment,type,text,YES,null
equipment,size,text,YES,null
equipment,serial_number,text,YES,null
equipment,condition,text,YES,null
equipment,is_available,boolean,YES,null
equipment,last_serviced,date,YES,null
equipment,notes,text,YES,null
equipment,id,uuid,NO,gen_random_uuid()
equipment,total_count,integer,YES,0
equipment,low_alert_threshold,integer,YES,0
equipment_rental_rates,created_at,timestamp with time zone,NO,now()
equipment_rental_rates,dive_center_id,uuid,YES,gen_random_uuid()
equipment_rental_rates,item_name,text,YES,null
equipment_rental_rates,rate,numeric,YES,null
equipment_rental_rates,charge_type,text,YES,null
equipment_rental_rates,is_active,boolean,YES,null
equipment_rental_rates,id,uuid,NO,gen_random_uuid()
exchange_rates,created_at,timestamp with time zone,NO,now()
exchange_rates,dive_center_id,uuid,YES,gen_random_uuid()
exchange_rates,currency_code,text,YES,null
exchange_rates,rate_to_php,numeric,YES,null
exchange_rates,is_active,boolean,YES,null
exchange_rates,updated_at,timestamp with time zone,YES,null
exchange_rates,id,uuid,NO,gen_random_uuid()
expenses,id,uuid,NO,gen_random_uuid()
expenses,dive_center_id,uuid,NO,null
expenses,date,date,NO,null
expenses,category,text,NO,null
expenses,custom_category,text,YES,null
expenses,amount,numeric,NO,0
expenses,paid_by,text,NO,null
expenses,notes,text,YES,null
expenses,created_by,uuid,YES,null
expenses,created_at,timestamp with time zone,YES,now()
fuel_logs,id,uuid,NO,gen_random_uuid()
fuel_logs,dive_center_id,uuid,NO,null
fuel_logs,schedule_id,uuid,NO,null
fuel_logs,boat_id,uuid,NO,null
fuel_logs,fuel_type,text,NO,null
fuel_logs,liters_consumed,numeric,NO,null
fuel_logs,diver_count,integer,NO,0
fuel_logs,dive_count,integer,NO,0
fuel_logs,created_at,timestamp with time zone,YES,now()
govt_fees,id,uuid,NO,gen_random_uuid()
govt_fees,dive_center_id,uuid,NO,null
govt_fees,date,date,NO,null
govt_fees,fee_type,text,NO,null
govt_fees,rate,numeric,NO,0
govt_fees,divers,integer,NO,0
govt_fees,total,numeric,NO,0
govt_fees,created_at,timestamp with time zone,YES,now()
groups,created_at,timestamp with time zone,NO,now()
groups,dive_center_id,uuid,YES,gen_random_uuid()
groups,group_name,text,YES,null
groups,leader_name,text,YES,null
groups,leader_email,text,YES,null
groups,leader_whatsapp,text,YES,null
groups,expected_count,smallint,YES,null
groups,arrival_date,date,YES,null
groups,notes,text,YES,null
groups,is_active,boolean,YES,null
groups,id,uuid,NO,gen_random_uuid()
groups,departure_date,date,YES,null
invoice_emails,id,uuid,NO,gen_random_uuid()
invoice_emails,dive_center_id,uuid,NO,null
invoice_emails,visit_id,uuid,NO,null
invoice_emails,diver_id,uuid,NO,null
invoice_emails,sent_at,timestamp with time zone,NO,now()
invoice_emails,sent_by,uuid,NO,null
invoice_emails,invoice_snapshot,jsonb,NO,null
invoice_emails,created_at,timestamp with time zone,NO,now()
join_ride_records,created_at,timestamp with time zone,NO,now()
join_ride_records,dive_center_id,uuid,YES,gen_random_uuid()
join_ride_records,direction,text,YES,null
join_ride_records,date,date,YES,null
join_ride_records,company,text,YES,null
join_ride_records,number_of_divers,integer,YES,0
join_ride_records,number_of_dives,integer,YES,0
join_ride_records,dive_sites,text,YES,null
join_ride_records,total_amount,numeric,YES,'0'::numeric
join_ride_records,status,text,YES,null
join_ride_records,balance,numeric,YES,'0'::numeric
join_ride_records,remarks,text,YES,null
join_ride_records,source_schedule_id,uuid,YES,gen_random_uuid()
join_ride_records,statement_id,uuid,YES,gen_random_uuid()
join_ride_records,updated_at,timestamp with time zone,YES,now()
join_ride_records,id,uuid,NO,gen_random_uuid()
join_ride_statements,created_at,timestamp with time zone,NO,now()
join_ride_statements,dive_center_id,uuid,YES,gen_random_uuid()
join_ride_statements,company,text,YES,null
join_ride_statements,date_from,date,YES,null
join_ride_statements,date_to,date,YES,null
join_ride_statements,total_amount,numeric,YES,'0'::numeric
join_ride_statements,status,text,YES,null
join_ride_statements,prepared_by,text,YES,null
join_ride_statements,printed_at,timestamp with time zone,YES,null
join_ride_statements,collected_at,timestamp with time zone,YES,null
join_ride_statements,remarks,text,YES,null
join_ride_statements,updated_at,timestamp with time zone,YES,now()
join_ride_statements,id,uuid,NO,gen_random_uuid()
joiner_groups,created_at,timestamp with time zone,NO,now()
joiner_groups,dive_center_id,uuid,YES,gen_random_uuid()
joiner_groups,schedule_id,uuid,YES,gen_random_uuid()
joiner_groups,from_company,text,YES,null
joiner_groups,diver_count,smallint,YES,null
joiner_groups,staff_count,smallint,YES,null
joiner_groups,contact_person,text,YES,null
joiner_groups,notes,text,YES,null
joiner_groups,id,uuid,NO,gen_random_uuid()
manifests,id,uuid,NO,gen_random_uuid()
manifests,dive_center_id,uuid,NO,null
manifests,schedule_id,uuid,NO,null
manifests,district,text,YES,null
manifests,port,text,YES,null
manifests,printed_at,timestamp with time zone,YES,null
manifests,locked,boolean,NO,false
manifests,unlocked_at,timestamp with time zone,YES,null
manifests,unlocked_by,uuid,YES,null
manifests,last_edited_at,timestamp with time zone,YES,null
manifests,created_at,timestamp with time zone,NO,now()
medical_questions,id,bigint,NO,null
medical_questions,created_at,timestamp with time zone,NO,now()
medical_questions,dive_center_id,uuid,YES,gen_random_uuid()
medical_questions,question_text,text,YES,null
medical_questions,is_active,boolean,YES,null
medical_questions,sort_order,smallint,YES,null
other_charges,created_at,timestamp with time zone,NO,now()
other_charges,dive_center_id,uuid,YES,gen_random_uuid()
other_charges,charge_name,text,YES,null
other_charges,amount,numeric,YES,null
other_charges,charge_type,text,YES,null
other_charges,is_active,boolean,YES,null
other_charges,id,uuid,NO,gen_random_uuid()
other_charges,sub_type,text,YES,null
packages,created_at,timestamp with time zone,NO,now()
packages,dive_center_id,uuid,YES,gen_random_uuid()
packages,package_name,text,YES,null
packages,dive_site,text,YES,null
packages,price,numeric,YES,null
packages,equipment_included,boolean,YES,null
packages,is_active,boolean,YES,null
packages,id,uuid,NO,gen_random_uuid()
payment_surcharges,created_at,timestamp with time zone,NO,now()
payment_surcharges,dive_center_id,uuid,YES,gen_random_uuid()
payment_surcharges,surcharge_type,text,YES,null
payment_surcharges,percentage,numeric,YES,null
payment_surcharges,id,uuid,NO,gen_random_uuid()
payments,created_at,timestamp with time zone,NO,now()
payments,dive_center_id,uuid,YES,gen_random_uuid()
payments,diver_id,uuid,YES,gen_random_uuid()
payments,cash_amount,numeric,YES,null
payments,card_amount,numeric,YES,null
payments,online_amount,numeric,YES,null
payments,total_paid,numeric,YES,null
payments,balance,numeric,YES,null
payments,currency,numeric,YES,null
payments,exchange_rate,numeric,YES,null
payments,grand_total_php,numeric,YES,null
payments,is_paid,boolean,YES,null
payments,paid_at,timestamp with time zone,YES,null
payments,notes,text,YES,null
payments,id,uuid,NO,gen_random_uuid()
payments,visit_id,uuid,YES,gen_random_uuid()
payments,card_surcharge_rate,numeric,YES,'5'::numeric
payments,online_surcharge_rate,numeric,YES,'2'::numeric
payments,card_surcharge_amount,numeric,YES,null
payments,online_surcharge_amount,numeric,YES,null
payments,total_surcharge,numeric,YES,null
payments,total_collected,numeric,YES,null
payments,discount,numeric,YES,0
payments,currency_code,text,YES,null
payments,cash_currency_code,text,YES,'PHP'::text
payments,cash_amount_foreign,numeric,YES,0
payments,cash_currency,text,YES,null
payments,cash_exchange_rate,numeric,YES,null
platform_admin_otp,id,uuid,NO,gen_random_uuid()
platform_admin_otp,purpose,text,NO,null
platform_admin_otp,dive_center_id,uuid,YES,null
platform_admin_otp,requested_by,uuid,NO,null
platform_admin_otp,code_hash,text,NO,null
platform_admin_otp,attempts,integer,NO,0
platform_admin_otp,max_attempts,integer,NO,5
platform_admin_otp,expires_at,timestamp with time zone,NO,null
platform_admin_otp,consumed_at,timestamp with time zone,YES,null
platform_admin_otp,otp_token,text,YES,null
platform_admin_otp,otp_token_expires_at,timestamp with time zone,YES,null
platform_admin_otp,otp_token_consumed_at,timestamp with time zone,YES,null
platform_admin_otp,created_at,timestamp with time zone,NO,now()
privacy_notice,id,boolean,NO,true
privacy_notice,content,text,YES,null
privacy_notice,updated_at,timestamp with time zone,YES,now()
privacy_notices,id,uuid,NO,gen_random_uuid()
privacy_notices,version,integer,NO,null
privacy_notices,content,text,NO,null
privacy_notices,is_current,boolean,NO,true
privacy_notices,created_at,timestamp with time zone,NO,now()
rate_tiers,created_at,timestamp with time zone,NO,now()
rate_tiers,dive_center_id,uuid,YES,gen_random_uuid()
rate_tiers,tier_from,smallint,YES,null
rate_tiers,tier_to,smallint,YES,null
rate_tiers,base_rate,numeric,YES,null
rate_tiers,id,uuid,NO,gen_random_uuid()
rate_tiers,rate_type,text,YES,null
rental_gear_records,created_at,timestamp with time zone,NO,now()
rental_gear_records,dive_center_id,uuid,YES,gen_random_uuid()
rental_gear_records,date,date,YES,null
rental_gear_records,equipment,text,YES,null
rental_gear_records,company,text,YES,null
rental_gear_records,quantity,integer,YES,0
rental_gear_records,rate,numeric,YES,'0'::numeric
rental_gear_records,total_amount,numeric,YES,'0'::numeric
rental_gear_records,status,text,YES,null
rental_gear_records,balance,numeric,YES,'0'::numeric
rental_gear_records,remarks,text,YES,null
rental_gear_records,updated_at,timestamp with time zone,YES,now()
rental_gear_records,id,uuid,NO,gen_random_uuid()
schedule_day_diver_exclusions,id,uuid,NO,gen_random_uuid()
schedule_day_diver_exclusions,created_at,timestamp with time zone,NO,now()
schedule_day_diver_exclusions,dive_center_id,uuid,NO,null
schedule_day_diver_exclusions,schedule_date,date,NO,null
schedule_day_diver_exclusions,diver_id,uuid,NO,null
schedule_day_diver_exclusions,created_by,uuid,YES,null
schedule_divers,created_at,timestamp with time zone,NO,now()
schedule_divers,schedule_id,uuid,YES,gen_random_uuid()
schedule_divers,diver_id,uuid,YES,gen_random_uuid()
schedule_divers,staff_id,uuid,YES,gen_random_uuid()
schedule_divers,is_group_leader,boolean,YES,null
schedule_divers,nitrox_requested,boolean,YES,null
schedule_divers,notes,text,YES,null
schedule_divers,id,uuid,NO,gen_random_uuid()
schedule_divers,is_diving_tomorrow,boolean,YES,null
schedule_divers,experience_type,text,YES,null
schedule_divers,dive_center_id,uuid,YES,null
schedule_divers,is_15l,boolean,YES,false
schedule_team_clip_divers,id,uuid,NO,gen_random_uuid()
schedule_team_clip_divers,created_at,timestamp with time zone,NO,now()
schedule_team_clip_divers,dive_center_id,uuid,NO,null
schedule_team_clip_divers,clip_id,uuid,NO,null
schedule_team_clip_divers,diver_id,uuid,NO,null
schedule_team_clip_divers,excluded_on_date,boolean,NO,false
schedule_team_clips,id,uuid,NO,gen_random_uuid()
schedule_team_clips,created_at,timestamp with time zone,NO,now()
schedule_team_clips,updated_at,timestamp with time zone,NO,now()
schedule_team_clips,dive_center_id,uuid,NO,null
schedule_team_clips,schedule_date,date,NO,null
schedule_team_clips,staff_id,uuid,YES,null
schedule_team_clips,staff_name,text,NO,null
schedule_team_clips,is_freelancer,boolean,NO,false
schedule_team_clips,source,text,NO,'manual'::text
schedule_team_clips,created_by,uuid,YES,null
schedule_team_clips,carry_forward,boolean,NO,true
schedules,created_at,timestamp with time zone,NO,now()
schedules,dive_center_id,uuid,YES,gen_random_uuid()
schedules,boat_id,uuid,YES,gen_random_uuid()
schedules,schedule_date,date,YES,null
schedules,dive_site,text,YES,null
schedules,departure_time,time without time zone,YES,null
schedules,air_tanks,smallint,YES,null
schedules,nitrox_tanks,smallint,YES,null
schedules,notes,text,YES,null
schedules,id,uuid,NO,gen_random_uuid()
schedules,is_joiner,boolean,YES,null
schedules,joiner_boat_name,text,YES,null
schedules,is_returned,boolean,NO,false
schedules,returned_at,timestamp with time zone,YES,null
schedules,manifest_id,uuid,YES,null
schedules,fuel_consumed_liters,numeric,YES,null
staff,created_at,timestamp with time zone,NO,now()
staff,dive_center_id,uuid,YES,gen_random_uuid()
staff,first_name,text,YES,null
staff,last_name,text,YES,null
staff,role,text,YES,null
staff,certification_level,text,YES,null
staff,phone,text,YES,null
staff,whatsapp,text,YES,null
staff,commission_rate,numeric,YES,null
staff,is_active,boolean,YES,null
staff,id,uuid,NO,gen_random_uuid()
staff,pay_type,text,YES,null
staff,salary_amount,numeric,YES,null
staff,daily_rate,numeric,YES,null
staff,date_hired,date,YES,null
staff,employment_status,text,YES,null
staff,access_level,text,YES,null
staff,email,text,YES,null
staff,nitrox_certified,boolean,YES,false
staff,auth_user_id,uuid,YES,null
staff_commission_records,created_at,timestamp with time zone,NO,now()
staff_commission_records,dive_center_id,uuid,YES,gen_random_uuid()
staff_commission_records,period_month,text,YES,null
staff_commission_records,staff_name,text,YES,null
staff_commission_records,commission_group,text,YES,null
staff_commission_records,title,text,YES,null
staff_commission_records,quantity,integer,YES,0
staff_commission_records,rate,numeric,YES,'0'::numeric
staff_commission_records,commission_amount,numeric,YES,'0'::numeric
staff_commission_records,status,text,YES,null
staff_commission_records,paid_at,timestamp with time zone,YES,null
staff_commission_records,remarks,text,YES,null
staff_commission_records,updated_at,timestamp with time zone,YES,now()
staff_commission_records,id,uuid,NO,gen_random_uuid()
staff_commission_records,add_on,numeric,YES,null
staff_commission_records,date,date,YES,null
staff_commission_records,additional_rate,numeric,NO,0
staff_commission_records,total_amount,numeric,NO,0
staff_commission_records,diver_name,text,YES,null
staff_commissions,created_at,timestamp with time zone,NO,now()
staff_commissions,dive_center_id,uuid,YES,gen_random_uuid()
staff_commissions,staff_id,uuid,YES,gen_random_uuid()
staff_commissions,activity_id,uuid,YES,gen_random_uuid()
staff_commissions,commission_type,text,YES,null
staff_commissions,commission_amount,numeric,YES,null
staff_commissions,payment_schedule,text,YES,null
staff_commissions,is_paid,boolean,YES,null
staff_commissions,paid_at,timestamp with time zone,YES,null
staff_commissions,notes,text,YES,null
staff_commissions,id,uuid,NO,gen_random_uuid()
tanks,created_at,timestamp with time zone,NO,now()
tanks,dive_center_id,uuid,YES,gen_random_uuid()
tanks,type,text,YES,null
tanks,total_count,smallint,YES,null
tanks,available_count,smallint,YES,null
tanks,in_use_count,smallint,YES,null
tanks,low_alert_threshold,smallint,YES,null
tanks,notes,text,YES,null
tanks,id,uuid,NO,gen_random_uuid()
users,created_at,timestamp with time zone,NO,now()
users,dive_center_id,uuid,YES,gen_random_uuid()
users,full_name,text,YES,null
users,email,text,YES,null
users,role,text,YES,null
users,is_active,boolean,YES,null
users,id,uuid,NO,gen_random_uuid()
users,can_view_revenue,boolean,NO,false
users,password_changed,boolean,NO,false
users,is_platform_admin,boolean,NO,false
users,failed_login_attempts,integer,NO,0
users,locked_until,timestamp with time zone,YES,null
visit_rate_selections,id,uuid,NO,gen_random_uuid()
visit_rate_selections,dive_center_id,uuid,NO,null
visit_rate_selections,visit_id,uuid,NO,null
visit_rate_selections,site_key,text,NO,null
visit_rate_selections,package_id,uuid,YES,null
visit_rate_selections,custom_price,numeric,YES,null
visit_rate_selections,created_at,timestamp with time zone,YES,now()
visits,created_at,timestamp with time zone,NO,now()
visits,dive_center_id,uuid,YES,gen_random_uuid()
visits,diver_id,uuid,YES,gen_random_uuid()
visits,visit_start,date,YES,null
visits,visit_end,date,YES,null
visits,is_active,boolean,YES,null
visits,is_paid,boolean,YES,null
visits,id,uuid,NO,gen_random_uuid()
visits,experience_type,text,YES,null
visits,visit_status,text,YES,'open'::text
visits,invoice_count,smallint,NO,0
visits,course_rate_id,uuid,YES,null
```

## `auth` schema — `users` / `identities`

```
table_name,column_name,data_type,is_nullable,column_default
identities,provider_id,text,NO,null
identities,user_id,uuid,NO,null
identities,identity_data,jsonb,NO,null
identities,provider,text,NO,null
identities,last_sign_in_at,timestamp with time zone,YES,null
identities,created_at,timestamp with time zone,YES,null
identities,updated_at,timestamp with time zone,YES,null
identities,email,text,YES,null
identities,id,uuid,NO,gen_random_uuid()
users,instance_id,uuid,YES,null
users,id,uuid,NO,null
users,aud,character varying,YES,null
users,role,character varying,YES,null
users,email,character varying,YES,null
users,encrypted_password,character varying,YES,null
users,email_confirmed_at,timestamp with time zone,YES,null
users,invited_at,timestamp with time zone,YES,null
users,confirmation_token,character varying,YES,null
users,confirmation_sent_at,timestamp with time zone,YES,null
users,recovery_token,character varying,YES,null
users,recovery_sent_at,timestamp with time zone,YES,null
users,email_change_token_new,character varying,YES,null
users,email_change,character varying,YES,null
users,email_change_sent_at,timestamp with time zone,YES,null
users,last_sign_in_at,timestamp with time zone,YES,null
users,raw_app_meta_data,jsonb,YES,null
users,raw_user_meta_data,jsonb,YES,null
users,is_super_admin,boolean,YES,null
users,created_at,timestamp with time zone,YES,null
users,updated_at,timestamp with time zone,YES,null
users,phone,text,YES,NULL::character varying
users,phone_confirmed_at,timestamp with time zone,YES,null
users,phone_change,text,YES,''::character varying
users,phone_change_token,character varying,YES,''::character varying
users,phone_change_sent_at,timestamp with time zone,YES,null
users,confirmed_at,timestamp with time zone,YES,null
users,email_change_token_current,character varying,YES,''::character varying
users,email_change_confirm_status,smallint,YES,0
users,banned_until,timestamp with time zone,YES,null
users,reauthentication_token,character varying,YES,''::character varying
users,reauthentication_sent_at,timestamp with time zone,YES,null
users,is_sso_user,boolean,NO,false
users,deleted_at,timestamp with time zone,YES,null
users,is_anonymous,boolean,NO,false
```

**Note**: all the token columns this project has been bitten by before
(`confirmation_token`, `recovery_token`, `email_change_token_new`,
`email_change`, `email_change_token_current`, `phone_change`,
`phone_change_token`, `reauthentication_token`) default to `''` here, not
`null` — confirms real live rows should already be in the shape a verbatim
copy needs (see retrospective #26 in `CLAUDE.md`).

## Check constraints in `public`

```
conname,definition
audit_logs_action_check,"CHECK ((action = ANY (ARRAY['bill_unlocked'::text, 'manifest_unlocked'::text])))"
audit_logs_target_type_check,"CHECK ((target_type = ANY (ARRAY['visit'::text, 'manifest'::text])))"
fuel_logs_fuel_type_check,"CHECK ((fuel_type = ANY (ARRAY['gasoline'::text, 'diesel'::text])))"
privacy_notice_singleton,CHECK (id)
schedule_team_clips_source_check,"CHECK ((source = ANY (ARRAY['manual'::text, 'returned'::text, 'carryover'::text])))"
visit_rate_selections_check,CHECK (((package_id IS NOT NULL) OR (custom_price IS NOT NULL)))
```

Notably: almost nothing else in the live schema is constrained by a real
`check` — most "enum-like" old columns (`activities.status`,
`boats.boat_type`, `staff.employment_status`, `expenses.category`, etc.)
are plain `text` with **no DB-level constraint at all**. Whatever values
are actually in the data is whatever the old app's UI happened to send —
worth a real `select distinct` audit per column before writing the ETL's
value-transform lookup tables, not just trusting the JS-derived value
lists in `LIVE_DATA_MIGRATION_MAPPING.md`.

---

## Corrections / new findings vs. `LIVE_DATA_MIGRATION_MAPPING.md`

This snapshot surfaced real discrepancies against the JS-only mapping.
A follow-up static-analysis pass (2026-08-07, grepping the actual old
HTML/JS reference files) resolved every item below to a confirmed
live/dead status. **Net effect: good news — almost everything turned out
to be dead legacy cruft.** This *simplifies* the ETL: dead tables/columns
are just excluded entirely, nothing new needs to be added to the
recommended table list or build order in `LIVE_DATA_MIGRATION_MAPPING.md`.

1. **`medical_questions.sort_order` already exists on the OLD schema** —
   confirmed real. Copy directly; no synthesis from `created_at` needed
   (this was the one item that actually simplifies the ETL script itself,
   not just the investigation scope).
2. **`staff_commissions`** (distinct from `staff_commission_records`) —
   **dead**. Zero references anywhere in `reports.html`/`staff.html`. The
   only staff-payout table the app touches is the already-mapped
   `staff_commission_records`. **Do not migrate.**
3. **`activity_rates`** — **dead**. Zero references in `settings.html`/
   `diver-form.html`. Real pricing config lives in `rate_tiers`/
   `packages`/`course_rates` (all already mapped). **Do not migrate.**
4. **`billing_payments`** — **unconfirmed, but out of scope regardless.**
   "Mark as Paid"/"Start Billing" in `office.html` call a service-role
   Edge Function (`mark_paid`/`start_billing`) whose source isn't on
   disk — whether it also inserts into `billing_payments` can't be
   determined by static analysis. Moot either way: this is
   platform-billing history (subscription/invoicing for the dive center
   as a *customer of AquaDesk*), not tenant operational data, so it's
   out of scope for the per-dive-center data migration regardless of
   whether it's live.
5. **`diver_equipment`** — **dead**. Zero references in `divers.html`/
   `diver-form.html`. Equipment is tracked only via the already-mapped
   `divers.needs_equipment`/`equipment_requested`. **Do not migrate.**
6. **`joiner_groups`** — **dead**. Zero references in `scheduling.html`.
   Confirms the original mapping was right the first time: "another dive
   center joined us" (diver count/company/notes) really does live only
   inside `schedules.notes`' JSON blob (`joinerDivers`/`joinerDC`/
   `joinerNotes`), exactly as `LIVE_DATA_MIGRATION_MAPPING.md` already
   documents. **Do not migrate `joiner_groups`; no change to the ETL
   source for `guest_divers_count`/`guest_dive_center_name`/`guest_notes`.**
7. **`privacy_notices` (plural)** / **`divers.privacy_notice_id`** —
   **dead**, both. Zero references. Only the singleton `privacy_notice`
   (already mapped) is live. **Do not migrate either.**
8. **`manifests.locked`/`unlocked_at`/`unlocked_by`** — **effectively
   dead.** `locked` is read once, purely to append a "🔒" to a dropdown
   label (`scheduling.html`); `boat-manifest.html`'s lock-banner markup
   is never actually rendered (dead CSS rule, no DOM element uses it),
   and nothing anywhere writes `locked:true`/`unlocked_at`/`unlocked_by`
   — there is no real lock/unlock flow in the current app despite the
   columns and the `manifest_unlocked` audit-log action existing.
   **Skip these three columns; a bare `false`/`null` default is
   accurate, not a loss.**
9. **`schedules.air_tanks`/`nitrox_tanks`** — **dead**, confirmed
   superseded. Zero references to these exact columns — all per-dive
   tank tracking is in-memory/JSON, persisted into `activities.notes`
   (already the documented mechanism). **Do not migrate.**
10. **`schedules.manifest_id`** — **dead** as a link mechanism.
    `boat-manifest.html` matches manifests to schedules by querying
    `manifests` and matching client-side on `schedule_id`, never by
    reading a `schedules.manifest_id` column. Confirms the
    trigger-only-link assumption already in the mapping doc — no ETL
    change needed.
11. **`boats.type`** — **dead**. Zero references anywhere; `boat_type`
    (already mapped) is the one real column, confirmed directly in
    `settings.html`'s Fleet tab CRUD. **Do not migrate `type`.**
12. **`staff.certification_level`/`commission_rate`/`pay_type`/
    `salary_amount`** — **dead**, all four. Zero matches in
    `settings.html`/`staff.html`/`reports.html` (the one apparent
    `certification_level` hit in `staff.html` is actually a `divers`
    query, not `staff`). Real staff compensation is driven entirely by
    the already-mapped `staff.daily_rate` plus Reports' own commission
    settings. **Do not migrate any of these four.**
13. **`activities.staff_id`** — **dead for writes**, weak legacy-fallback
    for reads only. Every real Boat Return insert/update writes
    `staff_name` only, never `staff_id`. `reports.html` has one
    defensive fallback read (`staffNameFromActivity`) for hypothetical
    old rows, but nothing populates it going forward. **Do not migrate
    — `staff_name` (already mapped) is the real field.**
14. **`activities.fee_15l` vs `fifteen_l_fee`** — **both live, as a
    legacy/current pair.** Boat Return always hardcodes `fee_15l:0`
    while writing a real computed value to `fifteen_l_fee` (already
    mapped, the correct source); `diver-form.html` reads/edits
    `fifteen_l_fee` exclusively; `divers.html` has one defensive
    fallback read (`fifteen_l_fee||fee_15l`). **Migrate `fifteen_l_fee`
    only — `fee_15l` should just be left at its default `0` for
    migrated rows, matching what the live app itself always writes
    there.**
15. **Enum/free-text value-list spot check** (`activities.status`,
    `boats.boat_type`, `staff.employment_status`,
    `expenses.category`) — all four confirmed to exactly match the
    value lists already documented in `LIVE_DATA_MIGRATION_MAPPING.md`,
    nothing incomplete or miscased found.

**Bottom line for the ETL**: no new tables need to be added to the
migration scope, and no existing table mapping needs structural rework.
The only concrete script-level actions from this pass are (a) copy
`medical_questions.sort_order` directly instead of synthesizing it, and
(b) when mapping `activities`, read from `fifteen_l_fee`/`staff_name`
only — ignore `fee_15l`/`staff_id` entirely, they're legacy-only.
