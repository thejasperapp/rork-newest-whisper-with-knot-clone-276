/* eslint-disable */
// AUTO-GENERATED — DO NOT EDIT
// Run migrations to regenerate.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      account_link_codes: {
        Row: {
          code: string
          consumed_at: string | null
          consumed_by: string | null
          created_at: string
          expires_at: string
          jasper_uid: string
        }
        Insert: {
          code: string
          consumed_at?: string | null
          consumed_by?: string | null
          created_at?: string
          expires_at: string
          jasper_uid: string
        }
        Update: {
          code?: string
          consumed_at?: string | null
          consumed_by?: string | null
          created_at?: string
          expires_at?: string
          jasper_uid?: string
        }
        Relationships: []
      }
      account_link_intents: {
        Row: {
          code_challenge: string
          consent_version: string | null
          created_at: string
          expires_at: string
          id: string
          jasper_uid: string
          link_generation: string | null
          link_id: string | null
          requester_uid: string
          responded_at: string | null
          state: string
        }
        Insert: {
          code_challenge: string
          consent_version?: string | null
          created_at?: string
          expires_at?: string
          id: string
          jasper_uid: string
          link_generation?: string | null
          link_id?: string | null
          requester_uid: string
          responded_at?: string | null
          state?: string
        }
        Update: {
          code_challenge?: string
          consent_version?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          jasper_uid?: string
          link_generation?: string | null
          link_id?: string | null
          requester_uid?: string
          responded_at?: string | null
          state?: string
        }
        Relationships: []
      }
      account_links: {
        Row: {
          id: string
          jasper_uid: string
          linked_at: string
          revoked_at: string | null
          whisper_uid: string
        }
        Insert: {
          id?: string
          jasper_uid: string
          linked_at?: string
          revoked_at?: string | null
          whisper_uid: string
        }
        Update: {
          id?: string
          jasper_uid?: string
          linked_at?: string
          revoked_at?: string | null
          whisper_uid?: string
        }
        Relationships: []
      }
      business_ad_events: {
        Row: {
          ad_id: string
          created_at: string
          id: number
          kind: string
          viewer_id: string | null
        }
        Insert: {
          ad_id: string
          created_at?: string
          id?: never
          kind: string
          viewer_id?: string | null
        }
        Update: {
          ad_id?: string
          created_at?: string
          id?: never
          kind?: string
          viewer_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "business_ad_events_ad_id_fkey"
            columns: ["ad_id"]
            isOneToOne: false
            referencedRelation: "business_ads"
            referencedColumns: ["id"]
          },
        ]
      }
      business_ad_sets: {
        Row: {
          campaign_id: string
          created_at: string
          daily_impression_cap: number
          end_at: string | null
          follower_max: number | null
          follower_min: number
          id: string
          name: string
          placement: string
          placements: string[] | null
          start_at: string
          status: string
          target_roles: string[] | null
          updated_at: string
          user_id: string
        }
        Insert: {
          campaign_id: string
          created_at?: string
          daily_impression_cap?: number
          end_at?: string | null
          follower_max?: number | null
          follower_min?: number
          id?: string
          name: string
          placement?: string
          placements?: string[] | null
          start_at?: string
          status?: string
          target_roles?: string[] | null
          updated_at?: string
          user_id: string
        }
        Update: {
          campaign_id?: string
          created_at?: string
          daily_impression_cap?: number
          end_at?: string | null
          follower_max?: number | null
          follower_min?: number
          id?: string
          name?: string
          placement?: string
          placements?: string[] | null
          start_at?: string
          status?: string
          target_roles?: string[] | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "business_ad_sets_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "business_campaigns"
            referencedColumns: ["id"]
          },
        ]
      }
      business_ads: {
        Row: {
          ad_set_id: string | null
          body: string | null
          campaign_id: string | null
          created_at: string
          cta_label: string
          cta_url: string | null
          daily_budget_cents: number
          daily_impression_cap: number
          end_at: string | null
          headline: string
          id: string
          image_url: string | null
          media_type: string
          name: string
          placement: string
          profile_id: string | null
          start_at: string
          status: string
          target_roles: string[] | null
          total_budget_cents: number
          updated_at: string
          user_id: string
          video_url: string | null
        }
        Insert: {
          ad_set_id?: string | null
          body?: string | null
          campaign_id?: string | null
          created_at?: string
          cta_label?: string
          cta_url?: string | null
          daily_budget_cents?: number
          daily_impression_cap?: number
          end_at?: string | null
          headline: string
          id?: string
          image_url?: string | null
          media_type?: string
          name: string
          placement?: string
          profile_id?: string | null
          start_at?: string
          status?: string
          target_roles?: string[] | null
          total_budget_cents?: number
          updated_at?: string
          user_id: string
          video_url?: string | null
        }
        Update: {
          ad_set_id?: string | null
          body?: string | null
          campaign_id?: string | null
          created_at?: string
          cta_label?: string
          cta_url?: string | null
          daily_budget_cents?: number
          daily_impression_cap?: number
          end_at?: string | null
          headline?: string
          id?: string
          image_url?: string | null
          media_type?: string
          name?: string
          placement?: string
          profile_id?: string | null
          start_at?: string
          status?: string
          target_roles?: string[] | null
          total_budget_cents?: number
          updated_at?: string
          user_id?: string
          video_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "business_ads_ad_set_id_fkey"
            columns: ["ad_set_id"]
            isOneToOne: false
            referencedRelation: "business_ad_sets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "business_ads_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "business_campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "business_ads_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "business_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      business_campaigns: {
        Row: {
          cpm_cents: number
          created_at: string
          id: string
          lifetime_budget_cents: number | null
          name: string
          objective: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          cpm_cents?: number
          created_at?: string
          id?: string
          lifetime_budget_cents?: number | null
          name: string
          objective?: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          cpm_cents?: number
          created_at?: string
          id?: string
          lifetime_budget_cents?: number | null
          name?: string
          objective?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      business_deals: {
        Row: {
          brand_name: string
          contact: string | null
          created_at: string
          creator_username: string | null
          id: string
          next_step: string | null
          notes: string | null
          stage: string
          updated_at: string
          user_id: string
          value_cents: number
        }
        Insert: {
          brand_name: string
          contact?: string | null
          created_at?: string
          creator_username?: string | null
          id?: string
          next_step?: string | null
          notes?: string | null
          stage?: string
          updated_at?: string
          user_id: string
          value_cents?: number
        }
        Update: {
          brand_name?: string
          contact?: string | null
          created_at?: string
          creator_username?: string | null
          id?: string
          next_step?: string | null
          notes?: string | null
          stage?: string
          updated_at?: string
          user_id?: string
          value_cents?: number
        }
        Relationships: []
      }
      business_profiles: {
        Row: {
          about: string | null
          category: string | null
          created_at: string
          email: string | null
          id: string
          logo_url: string | null
          name: string
          phone: string | null
          updated_at: string
          user_id: string
          website: string | null
        }
        Insert: {
          about?: string | null
          category?: string | null
          created_at?: string
          email?: string | null
          id?: string
          logo_url?: string | null
          name: string
          phone?: string | null
          updated_at?: string
          user_id: string
          website?: string | null
        }
        Update: {
          about?: string | null
          category?: string | null
          created_at?: string
          email?: string | null
          id?: string
          logo_url?: string | null
          name?: string
          phone?: string | null
          updated_at?: string
          user_id?: string
          website?: string | null
        }
        Relationships: []
      }
      coach_grant_codes: {
        Row: {
          coach_uid: string
          code: string
          consumed_at: string | null
          consumed_by: string | null
          created_at: string
          expires_at: string
          scope: string
        }
        Insert: {
          coach_uid: string
          code: string
          consumed_at?: string | null
          consumed_by?: string | null
          created_at?: string
          expires_at: string
          scope?: string
        }
        Update: {
          coach_uid?: string
          code?: string
          consumed_at?: string | null
          consumed_by?: string | null
          created_at?: string
          expires_at?: string
          scope?: string
        }
        Relationships: []
      }
      coach_grants: {
        Row: {
          client_uid: string
          coach_uid: string
          granted_at: string
          id: string
          revoked_at: string | null
          scope: string
          status: string
        }
        Insert: {
          client_uid: string
          coach_uid: string
          granted_at?: string
          id?: string
          revoked_at?: string | null
          scope?: string
          status?: string
        }
        Update: {
          client_uid?: string
          coach_uid?: string
          granted_at?: string
          id?: string
          revoked_at?: string | null
          scope?: string
          status?: string
        }
        Relationships: []
      }
      ember_messages: {
        Row: {
          content: string | null
          created_at: string
          id: number
          role: string
          session_id: string
          tokens_in: number | null
          tokens_out: number | null
          tool_name: string | null
          user_id: string
        }
        Insert: {
          content?: string | null
          created_at?: string
          id?: number
          role: string
          session_id: string
          tokens_in?: number | null
          tokens_out?: number | null
          tool_name?: string | null
          user_id: string
        }
        Update: {
          content?: string | null
          created_at?: string
          id?: number
          role?: string
          session_id?: string
          tokens_in?: number | null
          tokens_out?: number | null
          tool_name?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ember_messages_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "ember_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      ember_sessions: {
        Row: {
          ended_at: string | null
          id: string
          message_count: number
          started_at: string
          topic_summary: string | null
          user_id: string
        }
        Insert: {
          ended_at?: string | null
          id?: string
          message_count?: number
          started_at?: string
          topic_summary?: string | null
          user_id: string
        }
        Update: {
          ended_at?: string | null
          id?: string
          message_count?: number
          started_at?: string
          topic_summary?: string | null
          user_id?: string
        }
        Relationships: []
      }
      friend_requests: {
        Row: {
          created_at: string
          from_user_id: string
          from_username: string
          id: string
          responded_at: string | null
          status: string
          to_user_id: string
          to_username: string
        }
        Insert: {
          created_at?: string
          from_user_id: string
          from_username: string
          id?: string
          responded_at?: string | null
          status?: string
          to_user_id: string
          to_username: string
        }
        Update: {
          created_at?: string
          from_user_id?: string
          from_username?: string
          id?: string
          responded_at?: string | null
          status?: string
          to_user_id?: string
          to_username?: string
        }
        Relationships: []
      }
      friendships: {
        Row: {
          created_at: string
          friend_user_id: string
          friend_username: string
          user_id: string
        }
        Insert: {
          created_at?: string
          friend_user_id: string
          friend_username: string
          user_id: string
        }
        Update: {
          created_at?: string
          friend_user_id?: string
          friend_username?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_account_permissions_v1: {
        Row: {
          choices: Json
          owner_id: string
          revision: number
          updated_at: string
        }
        Insert: {
          choices?: Json
          owner_id: string
          revision?: number
          updated_at?: string
        }
        Update: {
          choices?: Json
          owner_id?: string
          revision?: number
          updated_at?: string
        }
        Relationships: []
      }
      jasper_achievements: {
        Row: {
          client_id: string
          created_at: string
          description: string | null
          icon: string | null
          id: string
          key: string
          rarity: string | null
          recorded_on: string
          title: string
          unlocked_at: string
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          created_at?: string
          description?: string | null
          icon?: string | null
          id?: string
          key: string
          rarity?: string | null
          recorded_on?: string
          title: string
          unlocked_at: string
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          description?: string | null
          icon?: string | null
          id?: string
          key?: string
          rarity?: string | null
          recorded_on?: string
          title?: string
          unlocked_at?: string
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_active_energy_daily: {
        Row: {
          active_energy_kcal: number
          basal_energy_kcal: number
          client_id: string
          created_at: string
          exercise_minutes: number
          id: string
          move_goal_kcal: number | null
          recorded_on: string
          source: string | null
          stand_hours: number
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          active_energy_kcal?: number
          basal_energy_kcal?: number
          client_id: string
          created_at?: string
          exercise_minutes?: number
          id?: string
          move_goal_kcal?: number | null
          recorded_on: string
          source?: string | null
          stand_hours?: number
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          active_energy_kcal?: number
          basal_energy_kcal?: number
          client_id?: string
          created_at?: string
          exercise_minutes?: number
          id?: string
          move_goal_kcal?: number | null
          recorded_on?: string
          source?: string | null
          stand_hours?: number
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_agent_tasks: {
        Row: {
          applied_at: string | null
          capability: string
          created_at: string
          document_id: string | null
          expires_at: string
          forgotten: boolean
          id: string
          instruction: string
          owner_id: string
          preference_revision: number
          proposal: Json | null
          proposal_hash: string | null
          proposal_id: string | null
          proposal_until: string | null
          result_seq: number | null
          revision: number
          status: string
          workspace: string
        }
        Insert: {
          applied_at?: string | null
          capability: string
          created_at?: string
          document_id?: string | null
          expires_at?: string
          forgotten?: boolean
          id: string
          instruction: string
          owner_id: string
          preference_revision: number
          proposal?: Json | null
          proposal_hash?: string | null
          proposal_id?: string | null
          proposal_until?: string | null
          result_seq?: number | null
          revision?: number
          status?: string
          workspace?: string
        }
        Update: {
          applied_at?: string | null
          capability?: string
          created_at?: string
          document_id?: string | null
          expires_at?: string
          forgotten?: boolean
          id?: string
          instruction?: string
          owner_id?: string
          preference_revision?: number
          proposal?: Json | null
          proposal_hash?: string | null
          proposal_id?: string | null
          proposal_until?: string | null
          result_seq?: number | null
          revision?: number
          status?: string
          workspace?: string
        }
        Relationships: []
      }
      jasper_ai_chat_receipts_v1: {
        Row: {
          action: string
          operation_id: string
          owner_id: string
          revision: number
          thread_id: string
        }
        Insert: {
          action: string
          operation_id: string
          owner_id: string
          revision: number
          thread_id: string
        }
        Update: {
          action?: string
          operation_id?: string
          owner_id?: string
          revision?: number
          thread_id?: string
        }
        Relationships: []
      }
      jasper_ai_conversations_v1: {
        Row: {
          deleted: boolean
          id: string
          last_operation: string
          owner_id: string
          payload: string | null
          revision: number
          title: string
          updated_at: string
        }
        Insert: {
          deleted?: boolean
          id: string
          last_operation: string
          owner_id: string
          payload?: string | null
          revision?: number
          title: string
          updated_at?: string
        }
        Update: {
          deleted?: boolean
          id?: string
          last_operation?: string
          owner_id?: string
          payload?: string | null
          revision?: number
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      jasper_ai_daily_usage: {
        Row: {
          calls: number
          day: string
          feature: string
          user_id: string
        }
        Insert: {
          calls?: number
          day: string
          feature: string
          user_id: string
        }
        Update: {
          calls?: number
          day?: string
          feature?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_biological_age: {
        Row: {
          biological_age: number
          chronological_age: number
          client_id: string
          confidence: number | null
          confidence_level: string | null
          created_at: string
          delta_years: number
          factors: Json | null
          id: string
          recorded_on: string
          top_factor: string | null
          updated_at: string
          used_blood_biomarkers: boolean
          user_id: string
          visibility: string
        }
        Insert: {
          biological_age: number
          chronological_age: number
          client_id: string
          confidence?: number | null
          confidence_level?: string | null
          created_at?: string
          delta_years: number
          factors?: Json | null
          id?: string
          recorded_on: string
          top_factor?: string | null
          updated_at?: string
          used_blood_biomarkers?: boolean
          user_id: string
          visibility?: string
        }
        Update: {
          biological_age?: number
          chronological_age?: number
          client_id?: string
          confidence?: number | null
          confidence_level?: string | null
          created_at?: string
          delta_years?: number
          factors?: Json | null
          id?: string
          recorded_on?: string
          top_factor?: string | null
          updated_at?: string
          used_blood_biomarkers?: boolean
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_blood_panels: {
        Row: {
          albumin_g_dl: number | null
          alp_u_l: number | null
          client_id: string
          created_at: string
          creatinine_mg_dl: number | null
          crp_mg_l: number | null
          drawn_on: string
          glucose_mg_dl: number | null
          id: string
          lymphocyte_pct: number | null
          marker_count: number
          mcv_fl: number | null
          pheno_age: number | null
          rdw_pct: number | null
          source: string
          updated_at: string
          user_id: string
          visibility: string
          wbc_1000_ul: number | null
        }
        Insert: {
          albumin_g_dl?: number | null
          alp_u_l?: number | null
          client_id: string
          created_at?: string
          creatinine_mg_dl?: number | null
          crp_mg_l?: number | null
          drawn_on: string
          glucose_mg_dl?: number | null
          id?: string
          lymphocyte_pct?: number | null
          marker_count?: number
          mcv_fl?: number | null
          pheno_age?: number | null
          rdw_pct?: number | null
          source?: string
          updated_at?: string
          user_id: string
          visibility?: string
          wbc_1000_ul?: number | null
        }
        Update: {
          albumin_g_dl?: number | null
          alp_u_l?: number | null
          client_id?: string
          created_at?: string
          creatinine_mg_dl?: number | null
          crp_mg_l?: number | null
          drawn_on?: string
          glucose_mg_dl?: number | null
          id?: string
          lymphocyte_pct?: number | null
          marker_count?: number
          mcv_fl?: number | null
          pheno_age?: number | null
          rdw_pct?: number | null
          source?: string
          updated_at?: string
          user_id?: string
          visibility?: string
          wbc_1000_ul?: number | null
        }
        Relationships: []
      }
      jasper_body_metrics: {
        Row: {
          arm_cm: number | null
          bmi: number | null
          body_fat_pct: number | null
          bone_mass_kg: number | null
          chest_cm: number | null
          client_id: string
          created_at: string
          hips_cm: number | null
          id: string
          muscle_mass_kg: number | null
          recorded_on: string
          source: string | null
          thigh_cm: number | null
          updated_at: string
          user_id: string
          visibility: string
          waist_cm: number | null
          water_pct: number | null
          weight_kg: number | null
        }
        Insert: {
          arm_cm?: number | null
          bmi?: number | null
          body_fat_pct?: number | null
          bone_mass_kg?: number | null
          chest_cm?: number | null
          client_id: string
          created_at?: string
          hips_cm?: number | null
          id?: string
          muscle_mass_kg?: number | null
          recorded_on: string
          source?: string | null
          thigh_cm?: number | null
          updated_at?: string
          user_id: string
          visibility?: string
          waist_cm?: number | null
          water_pct?: number | null
          weight_kg?: number | null
        }
        Update: {
          arm_cm?: number | null
          bmi?: number | null
          body_fat_pct?: number | null
          bone_mass_kg?: number | null
          chest_cm?: number | null
          client_id?: string
          created_at?: string
          hips_cm?: number | null
          id?: string
          muscle_mass_kg?: number | null
          recorded_on?: string
          source?: string | null
          thigh_cm?: number | null
          updated_at?: string
          user_id?: string
          visibility?: string
          waist_cm?: number | null
          water_pct?: number | null
          weight_kg?: number | null
        }
        Relationships: []
      }
      jasper_chat_messages: {
        Row: {
          attachments: Json | null
          category: string | null
          client_id: string
          content: string
          created_at: string
          id: string
          reasoning: Json | null
          role: string
          sent_at: string
          thread_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          attachments?: Json | null
          category?: string | null
          client_id: string
          content: string
          created_at?: string
          id?: string
          reasoning?: Json | null
          role: string
          sent_at?: string
          thread_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          attachments?: Json | null
          category?: string | null
          client_id?: string
          content?: string
          created_at?: string
          id?: string
          reasoning?: Json | null
          role?: string
          sent_at?: string
          thread_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_chat_messages_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "jasper_chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_chat_threads: {
        Row: {
          client_id: string
          coach_mode: string | null
          created_at: string
          id: string
          is_private: boolean
          last_message_at: string | null
          title: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          client_id: string
          coach_mode?: string | null
          created_at?: string
          id?: string
          is_private?: boolean
          last_message_at?: string | null
          title?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          client_id?: string
          coach_mode?: string | null
          created_at?: string
          id?: string
          is_private?: boolean
          last_message_at?: string | null
          title?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_connect_dispatch: {
        Row: {
          id: boolean
          key_hash: string
          updated_at: string
        }
        Insert: {
          id?: boolean
          key_hash: string
          updated_at?: string
        }
        Update: {
          id?: boolean
          key_hash?: string
          updated_at?: string
        }
        Relationships: []
      }
      jasper_connect_event_journal: {
        Row: {
          captured_at: string
          event: string
          event_id: number
          occurred_at: string
          position: number | null
          ref_id: string | null
          resource: string
          user_id: string
        }
        Insert: {
          captured_at?: string
          event: string
          event_id: number
          occurred_at: string
          position?: number | null
          ref_id?: string | null
          resource: string
          user_id: string
        }
        Update: {
          captured_at?: string
          event?: string
          event_id?: number
          occurred_at?: string
          position?: number | null
          ref_id?: string | null
          resource?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_connect_event_journal_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: true
            referencedRelation: "jasper_connect_events"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_connect_events: {
        Row: {
          event: string
          id: number
          occurred_at: string
          ref_id: string | null
          resource: string
          user_id: string
        }
        Insert: {
          event: string
          id?: never
          occurred_at?: string
          ref_id?: string | null
          resource: string
          user_id: string
        }
        Update: {
          event?: string
          id?: never
          occurred_at?: string
          ref_id?: string | null
          resource?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_connect_requests: {
        Row: {
          app_name: string
          claimed_at: string | null
          code_challenge: string | null
          created_at: string
          expires_at: string
          id: string
          kind: string
          requester_uid: string
          responded_at: string | null
          scopes: string[]
          status: string
          target_uid: string
          token_id: string | null
        }
        Insert: {
          app_name: string
          claimed_at?: string | null
          code_challenge?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          kind?: string
          requester_uid: string
          responded_at?: string | null
          scopes: string[]
          status?: string
          target_uid: string
          token_id?: string | null
        }
        Update: {
          app_name?: string
          claimed_at?: string | null
          code_challenge?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          kind?: string
          requester_uid?: string
          responded_at?: string | null
          scopes?: string[]
          status?: string
          target_uid?: string
          token_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "jasper_connect_requests_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "jasper_connect_tokens"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_connect_stream_heads: {
        Row: {
          floor: number
          position: number
          started_at: string
          user_id: string
        }
        Insert: {
          floor?: number
          position?: number
          started_at?: string
          user_id: string
        }
        Update: {
          floor?: number
          position?: number
          started_at?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_connect_tokens: {
        Row: {
          app_name: string
          created_at: string
          created_via: string
          expires_at: string | null
          grantee_uid: string | null
          id: string
          kind: string
          last_used_at: string | null
          revoked_at: string | null
          scopes: string[]
          token_hash: string
          token_prefix: string
          user_id: string
        }
        Insert: {
          app_name: string
          created_at?: string
          created_via?: string
          expires_at?: string | null
          grantee_uid?: string | null
          id?: string
          kind?: string
          last_used_at?: string | null
          revoked_at?: string | null
          scopes: string[]
          token_hash: string
          token_prefix: string
          user_id: string
        }
        Update: {
          app_name?: string
          created_at?: string
          created_via?: string
          expires_at?: string | null
          grantee_uid?: string | null
          id?: string
          kind?: string
          last_used_at?: string | null
          revoked_at?: string | null
          scopes?: string[]
          token_hash?: string
          token_prefix?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_connect_webhooks: {
        Row: {
          created_at: string
          cursor_id: number
          disabled_at: string | null
          disabled_reason: string | null
          event_filter: string[] | null
          failure_count: number
          id: string
          issued_cursor: number | null
          issued_delivery: string | null
          last_attempt_at: string | null
          last_delivery_at: string | null
          last_status: number | null
          lease_until: string | null
          next_attempt_at: string | null
          secret: string
          token_id: string
          url: string
          user_id: string
        }
        Insert: {
          created_at?: string
          cursor_id?: number
          disabled_at?: string | null
          disabled_reason?: string | null
          event_filter?: string[] | null
          failure_count?: number
          id?: string
          issued_cursor?: number | null
          issued_delivery?: string | null
          last_attempt_at?: string | null
          last_delivery_at?: string | null
          last_status?: number | null
          lease_until?: string | null
          next_attempt_at?: string | null
          secret: string
          token_id: string
          url: string
          user_id: string
        }
        Update: {
          created_at?: string
          cursor_id?: number
          disabled_at?: string | null
          disabled_reason?: string | null
          event_filter?: string[] | null
          failure_count?: number
          id?: string
          issued_cursor?: number | null
          issued_delivery?: string | null
          last_attempt_at?: string | null
          last_delivery_at?: string | null
          last_status?: number | null
          lease_until?: string | null
          next_attempt_at?: string | null
          secret?: string
          token_id?: string
          url?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_connect_webhooks_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "jasper_connect_tokens"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_connect_write_receipts: {
        Row: {
          created_at: string
          fingerprint: string
          key_hash: string
          result: Json
          token_id: string
        }
        Insert: {
          created_at?: string
          fingerprint: string
          key_hash: string
          result: Json
          token_id: string
        }
        Update: {
          created_at?: string
          fingerprint?: string
          key_hash?: string
          result?: Json
          token_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_connect_write_receipts_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "jasper_connect_tokens"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_diet_plan_days: {
        Row: {
          client_id: string
          created_at: string
          day_index: number
          day_name: string | null
          id: string
          meal_count: number | null
          plan_id: string | null
          recorded_on: string
          total_calories: number | null
          total_carbs_g: number | null
          total_fat_g: number | null
          total_protein_g: number | null
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          created_at?: string
          day_index?: number
          day_name?: string | null
          id?: string
          meal_count?: number | null
          plan_id?: string | null
          recorded_on?: string
          total_calories?: number | null
          total_carbs_g?: number | null
          total_fat_g?: number | null
          total_protein_g?: number | null
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          day_index?: number
          day_name?: string | null
          id?: string
          meal_count?: number | null
          plan_id?: string | null
          recorded_on?: string
          total_calories?: number | null
          total_carbs_g?: number | null
          total_fat_g?: number | null
          total_protein_g?: number | null
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_diet_plan_days_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "jasper_diet_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_diet_plan_meal_swaps: {
        Row: {
          client_id: string
          created_at: string
          day_id: string | null
          day_index: number
          from_calories: number | null
          from_carbs_g: number | null
          from_fat_g: number | null
          from_meal_name: string | null
          from_payload: Json | null
          from_protein_g: number | null
          id: string
          meal_id: string | null
          meal_index: number
          meal_type: string | null
          plan_id: string | null
          reason: string | null
          swapped_at: string
          to_calories: number | null
          to_carbs_g: number | null
          to_fat_g: number | null
          to_meal_name: string | null
          to_payload: Json | null
          to_protein_g: number | null
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          created_at?: string
          day_id?: string | null
          day_index?: number
          from_calories?: number | null
          from_carbs_g?: number | null
          from_fat_g?: number | null
          from_meal_name?: string | null
          from_payload?: Json | null
          from_protein_g?: number | null
          id?: string
          meal_id?: string | null
          meal_index?: number
          meal_type?: string | null
          plan_id?: string | null
          reason?: string | null
          swapped_at?: string
          to_calories?: number | null
          to_carbs_g?: number | null
          to_fat_g?: number | null
          to_meal_name?: string | null
          to_payload?: Json | null
          to_protein_g?: number | null
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          day_id?: string | null
          day_index?: number
          from_calories?: number | null
          from_carbs_g?: number | null
          from_fat_g?: number | null
          from_meal_name?: string | null
          from_payload?: Json | null
          from_protein_g?: number | null
          id?: string
          meal_id?: string | null
          meal_index?: number
          meal_type?: string | null
          plan_id?: string | null
          reason?: string | null
          swapped_at?: string
          to_calories?: number | null
          to_carbs_g?: number | null
          to_fat_g?: number | null
          to_meal_name?: string | null
          to_payload?: Json | null
          to_protein_g?: number | null
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_diet_plan_meal_swaps_day_id_fkey"
            columns: ["day_id"]
            isOneToOne: false
            referencedRelation: "jasper_diet_plan_days"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jasper_diet_plan_meal_swaps_meal_id_fkey"
            columns: ["meal_id"]
            isOneToOne: false
            referencedRelation: "jasper_diet_plan_meals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jasper_diet_plan_meal_swaps_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "jasper_diet_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_diet_plan_meals: {
        Row: {
          calories_kcal: number
          carbs_g: number
          client_id: string
          created_at: string
          day_id: string | null
          day_index: number
          description: string | null
          fat_g: number
          id: string
          ingredients: Json | null
          meal_index: number
          meal_type: string | null
          name: string
          plan_id: string | null
          prep_time: string | null
          protein_g: number
          recorded_on: string
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          calories_kcal?: number
          carbs_g?: number
          client_id: string
          created_at?: string
          day_id?: string | null
          day_index?: number
          description?: string | null
          fat_g?: number
          id?: string
          ingredients?: Json | null
          meal_index?: number
          meal_type?: string | null
          name: string
          plan_id?: string | null
          prep_time?: string | null
          protein_g?: number
          recorded_on?: string
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          calories_kcal?: number
          carbs_g?: number
          client_id?: string
          created_at?: string
          day_id?: string | null
          day_index?: number
          description?: string | null
          fat_g?: number
          id?: string
          ingredients?: Json | null
          meal_index?: number
          meal_type?: string | null
          name?: string
          plan_id?: string | null
          prep_time?: string | null
          protein_g?: number
          recorded_on?: string
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_diet_plan_meals_day_id_fkey"
            columns: ["day_id"]
            isOneToOne: false
            referencedRelation: "jasper_diet_plan_days"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jasper_diet_plan_meals_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "jasper_diet_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_diet_plans: {
        Row: {
          client_id: string
          created_at: string
          dietary_preference: string | null
          goal: string | null
          id: string
          is_active: boolean
          meals_per_day: number | null
          name: string
          payload: Json | null
          recorded_on: string
          target_calories: number | null
          target_carbs_g: number | null
          target_fat_g: number | null
          target_protein_g: number | null
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          created_at?: string
          dietary_preference?: string | null
          goal?: string | null
          id?: string
          is_active?: boolean
          meals_per_day?: number | null
          name: string
          payload?: Json | null
          recorded_on?: string
          target_calories?: number | null
          target_carbs_g?: number | null
          target_fat_g?: number | null
          target_protein_g?: number | null
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          dietary_preference?: string | null
          goal?: string | null
          id?: string
          is_active?: boolean
          meals_per_day?: number | null
          name?: string
          payload?: Json | null
          recorded_on?: string
          target_calories?: number | null
          target_carbs_g?: number | null
          target_fat_g?: number | null
          target_protein_g?: number | null
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_exercises: {
        Row: {
          client_id: string
          created_at: string
          equipment: string | null
          id: string
          is_custom: boolean
          muscle_group: string | null
          name: string
          notes: string | null
          recorded_on: string
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          created_at?: string
          equipment?: string | null
          id?: string
          is_custom?: boolean
          muscle_group?: string | null
          name: string
          notes?: string | null
          recorded_on?: string
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          equipment?: string | null
          id?: string
          is_custom?: boolean
          muscle_group?: string | null
          name?: string
          notes?: string | null
          recorded_on?: string
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_files: {
        Row: {
          body: string | null
          category: string | null
          client_id: string
          created_at: string
          id: string
          is_pinned: boolean
          kind: string
          payload: Json | null
          recorded_on: string
          source_message_id: string | null
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          body?: string | null
          category?: string | null
          client_id: string
          created_at?: string
          id?: string
          is_pinned?: boolean
          kind: string
          payload?: Json | null
          recorded_on?: string
          source_message_id?: string | null
          title: string
          updated_at?: string
          user_id: string
        }
        Update: {
          body?: string | null
          category?: string | null
          client_id?: string
          created_at?: string
          id?: string
          is_pinned?: boolean
          kind?: string
          payload?: Json | null
          recorded_on?: string
          source_message_id?: string | null
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_files_source_message_id_fkey"
            columns: ["source_message_id"]
            isOneToOne: false
            referencedRelation: "jasper_chat_messages"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_goals: {
        Row: {
          client_id: string
          completed_at: string | null
          created_at: string
          current_value: number | null
          due_date: string | null
          id: string
          is_complete: boolean
          kind: string
          notes: string | null
          recorded_on: string
          start_date: string | null
          target_unit: string | null
          target_value: number | null
          title: string
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          completed_at?: string | null
          created_at?: string
          current_value?: number | null
          due_date?: string | null
          id?: string
          is_complete?: boolean
          kind: string
          notes?: string | null
          recorded_on?: string
          start_date?: string | null
          target_unit?: string | null
          target_value?: number | null
          title: string
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          completed_at?: string | null
          created_at?: string
          current_value?: number | null
          due_date?: string | null
          id?: string
          is_complete?: boolean
          kind?: string
          notes?: string | null
          recorded_on?: string
          start_date?: string | null
          target_unit?: string | null
          target_value?: number | null
          title?: string
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_grocery_checks: {
        Row: {
          checked: boolean
          item_id: string
          plan_id: string
          source_app: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          checked?: boolean
          item_id: string
          plan_id: string
          source_app?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          checked?: boolean
          item_id?: string
          plan_id?: string
          source_app?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_health_uploads: {
        Row: {
          analysis: string | null
          category: string | null
          client_id: string
          created_at: string
          file_name: string | null
          id: string
          mime_type: string | null
          status: string
          storage_path: string
          updated_at: string
          uploaded_at: string
          user_id: string
        }
        Insert: {
          analysis?: string | null
          category?: string | null
          client_id: string
          created_at?: string
          file_name?: string | null
          id?: string
          mime_type?: string | null
          status?: string
          storage_path: string
          updated_at?: string
          uploaded_at?: string
          user_id: string
        }
        Update: {
          analysis?: string | null
          category?: string | null
          client_id?: string
          created_at?: string
          file_name?: string | null
          id?: string
          mime_type?: string | null
          status?: string
          storage_path?: string
          updated_at?: string
          uploaded_at?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_heart_rate_daily: {
        Row: {
          average_bpm: number | null
          client_id: string
          created_at: string
          hrv_ms: number | null
          id: string
          max_bpm: number | null
          min_bpm: number | null
          recorded_on: string
          resting_bpm: number | null
          source: string | null
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          average_bpm?: number | null
          client_id: string
          created_at?: string
          hrv_ms?: number | null
          id?: string
          max_bpm?: number | null
          min_bpm?: number | null
          recorded_on: string
          resting_bpm?: number | null
          source?: string | null
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          average_bpm?: number | null
          client_id?: string
          created_at?: string
          hrv_ms?: number | null
          id?: string
          max_bpm?: number | null
          min_bpm?: number | null
          recorded_on?: string
          resting_bpm?: number | null
          source?: string | null
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_intelligence: {
        Row: {
          owner_id: string
          revision: number
          tools: string[]
          updated_at: string
          workspace: string
        }
        Insert: {
          owner_id: string
          revision?: number
          tools?: string[]
          updated_at?: string
          workspace: string
        }
        Update: {
          owner_id?: string
          revision?: number
          tools?: string[]
          updated_at?: string
          workspace?: string
        }
        Relationships: []
      }
      jasper_intelligence_actions: {
        Row: {
          channel: string
          created_at: string
          expires_at: string
          id: string
          opened_at: string | null
          owner_id: string
          preference_revision: number
          status: string
          team_id: string | null
          tool: string
          workspace: string
        }
        Insert: {
          channel?: string
          created_at?: string
          expires_at?: string
          id: string
          opened_at?: string | null
          owner_id: string
          preference_revision: number
          status?: string
          team_id?: string | null
          tool: string
          workspace: string
        }
        Update: {
          channel?: string
          created_at?: string
          expires_at?: string
          id?: string
          opened_at?: string | null
          owner_id?: string
          preference_revision?: number
          status?: string
          team_id?: string | null
          tool?: string
          workspace?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_intelligence_actions_owner_id_workspace_fkey"
            columns: ["owner_id", "workspace"]
            isOneToOne: false
            referencedRelation: "jasper_intelligence"
            referencedColumns: ["owner_id", "workspace"]
          },
        ]
      }
      jasper_link_revocations: {
        Row: {
          revoked_at: string
          user_id: string
        }
        Insert: {
          revoked_at: string
          user_id: string
        }
        Update: {
          revoked_at?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_memory: {
        Row: {
          client_id: string
          created_at: string
          fact: string
          id: string
          kind: string | null
          recorded_on: string
          updated_at: string
          user_id: string
        }
        Insert: {
          client_id: string
          created_at?: string
          fact: string
          id?: string
          kind?: string | null
          recorded_on?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          client_id?: string
          created_at?: string
          fact?: string
          id?: string
          kind?: string | null
          recorded_on?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_nutrition_foods: {
        Row: {
          barcode: string | null
          brand: string | null
          calories_kcal: number
          carbs_g: number
          client_id: string
          created_at: string
          fat_g: number
          fiber_g: number
          id: string
          logged_at: string
          meal_id: string | null
          name: string
          protein_g: number
          serving_size: string | null
          servings: number
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          barcode?: string | null
          brand?: string | null
          calories_kcal?: number
          carbs_g?: number
          client_id: string
          created_at?: string
          fat_g?: number
          fiber_g?: number
          id?: string
          logged_at: string
          meal_id?: string | null
          name: string
          protein_g?: number
          serving_size?: string | null
          servings?: number
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          barcode?: string | null
          brand?: string | null
          calories_kcal?: number
          carbs_g?: number
          client_id?: string
          created_at?: string
          fat_g?: number
          fiber_g?: number
          id?: string
          logged_at?: string
          meal_id?: string | null
          name?: string
          protein_g?: number
          serving_size?: string | null
          servings?: number
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_nutrition_foods_meal_id_fkey"
            columns: ["meal_id"]
            isOneToOne: false
            referencedRelation: "jasper_nutrition_meals"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_nutrition_meals: {
        Row: {
          calories: number | null
          calories_kcal: number
          carbs_g: number
          client_id: string
          created_at: string
          eaten_at: string
          fat_g: number
          fiber_g: number
          foods: Json | null
          id: string
          logged_at: string
          meal_type: string | null
          name: string | null
          notes: string | null
          protein_g: number
          restaurant_name: string | null
          restaurant_place_id: string | null
          source: string | null
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          calories?: number | null
          calories_kcal?: number
          carbs_g?: number
          client_id: string
          created_at?: string
          eaten_at?: string
          fat_g?: number
          fiber_g?: number
          foods?: Json | null
          id?: string
          logged_at: string
          meal_type?: string | null
          name?: string | null
          notes?: string | null
          protein_g?: number
          restaurant_name?: string | null
          restaurant_place_id?: string | null
          source?: string | null
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          calories?: number | null
          calories_kcal?: number
          carbs_g?: number
          client_id?: string
          created_at?: string
          eaten_at?: string
          fat_g?: number
          fiber_g?: number
          foods?: Json | null
          id?: string
          logged_at?: string
          meal_type?: string | null
          name?: string | null
          notes?: string | null
          protein_g?: number
          restaurant_name?: string | null
          restaurant_place_id?: string | null
          source?: string | null
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_personal_records: {
        Row: {
          achieved_at: string
          client_id: string
          created_at: string
          exercise_name: string
          id: string
          record_type: string
          reps: number | null
          updated_at: string
          user_id: string
          value: number | null
          visibility: string
          weight_kg: number | null
          workout_id: string | null
        }
        Insert: {
          achieved_at: string
          client_id: string
          created_at?: string
          exercise_name: string
          id?: string
          record_type: string
          reps?: number | null
          updated_at?: string
          user_id: string
          value?: number | null
          visibility?: string
          weight_kg?: number | null
          workout_id?: string | null
        }
        Update: {
          achieved_at?: string
          client_id?: string
          created_at?: string
          exercise_name?: string
          id?: string
          record_type?: string
          reps?: number | null
          updated_at?: string
          user_id?: string
          value?: number | null
          visibility?: string
          weight_kg?: number | null
          workout_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "jasper_personal_records_workout_id_fkey"
            columns: ["workout_id"]
            isOneToOne: false
            referencedRelation: "jasper_workouts"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_personality_state_v1: {
        Row: {
          enabled: boolean
          generation: string
          owner_id: string
          preferences: Json
          revision: number
          updated_at: string
        }
        Insert: {
          enabled?: boolean
          generation?: string
          owner_id: string
          preferences?: Json
          revision?: number
          updated_at?: string
        }
        Update: {
          enabled?: boolean
          generation?: string
          owner_id?: string
          preferences?: Json
          revision?: number
          updated_at?: string
        }
        Relationships: []
      }
      jasper_plan_templates: {
        Row: {
          author_uid: string
          created_at: string
          goal: string | null
          id: string
          install_count: number
          kind: string
          payload: Json
          price_usd: number
          published: boolean
          purchase_url: string | null
          summary: string | null
          title: string
          top_level: Json
          updated_at: string
        }
        Insert: {
          author_uid: string
          created_at?: string
          goal?: string | null
          id?: string
          install_count?: number
          kind: string
          payload: Json
          price_usd?: number
          published?: boolean
          purchase_url?: string | null
          summary?: string | null
          title: string
          top_level?: Json
          updated_at?: string
        }
        Update: {
          author_uid?: string
          created_at?: string
          goal?: string | null
          id?: string
          install_count?: number
          kind?: string
          payload?: Json
          price_usd?: number
          published?: boolean
          purchase_url?: string | null
          summary?: string | null
          title?: string
          top_level?: Json
          updated_at?: string
        }
        Relationships: []
      }
      jasper_preferences: {
        Row: {
          client_id: string
          created_at: string
          dashboard_order: Json | null
          distance_unit: string
          energy_unit: string
          id: string
          notification_prefs: Json | null
          payload: Json | null
          recorded_on: string
          theme: string | null
          updated_at: string
          user_id: string
          visibility: string
          weight_unit: string
        }
        Insert: {
          client_id: string
          created_at?: string
          dashboard_order?: Json | null
          distance_unit?: string
          energy_unit?: string
          id?: string
          notification_prefs?: Json | null
          payload?: Json | null
          recorded_on?: string
          theme?: string | null
          updated_at?: string
          user_id: string
          visibility?: string
          weight_unit?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          dashboard_order?: Json | null
          distance_unit?: string
          energy_unit?: string
          id?: string
          notification_prefs?: Json | null
          payload?: Json | null
          recorded_on?: string
          theme?: string | null
          updated_at?: string
          user_id?: string
          visibility?: string
          weight_unit?: string
        }
        Relationships: []
      }
      jasper_private_items_v1: {
        Row: {
          deleted: boolean
          id: string
          kind: string
          owner_id: string
          payload: Json | null
          revision: number
          title: string
          updated_at: string
        }
        Insert: {
          deleted?: boolean
          id: string
          kind: string
          owner_id: string
          payload?: Json | null
          revision?: number
          title: string
          updated_at?: string
        }
        Update: {
          deleted?: boolean
          id?: string
          kind?: string
          owner_id?: string
          payload?: Json | null
          revision?: number
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      jasper_program_days: {
        Row: {
          client_id: string
          created_at: string
          day_index: number
          exercises: Json | null
          focus: string | null
          id: string
          name: string | null
          program_id: string | null
          recorded_on: string
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          created_at?: string
          day_index?: number
          exercises?: Json | null
          focus?: string | null
          id?: string
          name?: string | null
          program_id?: string | null
          recorded_on?: string
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          day_index?: number
          exercises?: Json | null
          focus?: string | null
          id?: string
          name?: string | null
          program_id?: string | null
          recorded_on?: string
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "jasper_program_days_program_id_fkey"
            columns: ["program_id"]
            isOneToOne: false
            referencedRelation: "jasper_programs"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_programs: {
        Row: {
          client_id: string
          coach_username: string | null
          created_at: string
          days_per_week: number | null
          description: string | null
          goal: string | null
          id: string
          name: string
          payload: Json | null
          recorded_on: string
          source: string | null
          updated_at: string
          user_id: string
          visibility: string
          weeks: number | null
        }
        Insert: {
          client_id: string
          coach_username?: string | null
          created_at?: string
          days_per_week?: number | null
          description?: string | null
          goal?: string | null
          id?: string
          name: string
          payload?: Json | null
          recorded_on?: string
          source?: string | null
          updated_at?: string
          user_id: string
          visibility?: string
          weeks?: number | null
        }
        Update: {
          client_id?: string
          coach_username?: string | null
          created_at?: string
          days_per_week?: number | null
          description?: string | null
          goal?: string | null
          id?: string
          name?: string
          payload?: Json | null
          recorded_on?: string
          source?: string | null
          updated_at?: string
          user_id?: string
          visibility?: string
          weeks?: number | null
        }
        Relationships: []
      }
      jasper_progress_photos: {
        Row: {
          caption: string | null
          client_id: string
          created_at: string
          id: string
          pose: string | null
          recorded_on: string
          storage_path: string
          thumb_path: string | null
          updated_at: string
          user_id: string
          visibility: string
          weight_kg: number | null
        }
        Insert: {
          caption?: string | null
          client_id: string
          created_at?: string
          id?: string
          pose?: string | null
          recorded_on: string
          storage_path: string
          thumb_path?: string | null
          updated_at?: string
          user_id: string
          visibility?: string
          weight_kg?: number | null
        }
        Update: {
          caption?: string | null
          client_id?: string
          created_at?: string
          id?: string
          pose?: string | null
          recorded_on?: string
          storage_path?: string
          thumb_path?: string | null
          updated_at?: string
          user_id?: string
          visibility?: string
          weight_kg?: number | null
        }
        Relationships: []
      }
      jasper_readiness_scores: {
        Row: {
          client_id: string
          created_at: string
          hrv_ms: number | null
          id: string
          notes: string | null
          recorded_on: string
          recovery_score: number | null
          resting_hr_bpm: number | null
          score: number
          sleep_score: number | null
          strain_score: number | null
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          created_at?: string
          hrv_ms?: number | null
          id?: string
          notes?: string | null
          recorded_on: string
          recovery_score?: number | null
          resting_hr_bpm?: number | null
          score: number
          sleep_score?: number | null
          strain_score?: number | null
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          hrv_ms?: number | null
          id?: string
          notes?: string | null
          recorded_on?: string
          recovery_score?: number | null
          resting_hr_bpm?: number | null
          score?: number
          sleep_score?: number | null
          strain_score?: number | null
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_recipes: {
        Row: {
          calories_per_serving: number | null
          carbs_g: number | null
          client_id: string
          cook_time: string | null
          created_at: string
          emoji: string | null
          fat_g: number | null
          id: string
          ingredients: Json
          name: string
          note: string
          payload: Json
          prep_time: string | null
          protein_g: number | null
          servings: number
          source_app: string | null
          source_url: string | null
          steps: Json
          updated_at: string
          user_id: string
        }
        Insert: {
          calories_per_serving?: number | null
          carbs_g?: number | null
          client_id: string
          cook_time?: string | null
          created_at?: string
          emoji?: string | null
          fat_g?: number | null
          id?: string
          ingredients?: Json
          name: string
          note?: string
          payload: Json
          prep_time?: string | null
          protein_g?: number | null
          servings?: number
          source_app?: string | null
          source_url?: string | null
          steps?: Json
          updated_at?: string
          user_id: string
        }
        Update: {
          calories_per_serving?: number | null
          carbs_g?: number | null
          client_id?: string
          cook_time?: string | null
          created_at?: string
          emoji?: string | null
          fat_g?: number | null
          id?: string
          ingredients?: Json
          name?: string
          note?: string
          payload?: Json
          prep_time?: string | null
          protein_g?: number | null
          servings?: number
          source_app?: string | null
          source_url?: string | null
          steps?: Json
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_shared_charts: {
        Row: {
          app_name: string
          author_uid: string | null
          chart: Json | null
          created_at: string
          id: string
          kind: string
          note: string | null
          seen_at: string | null
          title: string
          user_id: string
        }
        Insert: {
          app_name: string
          author_uid?: string | null
          chart?: Json | null
          created_at?: string
          id?: string
          kind?: string
          note?: string | null
          seen_at?: string | null
          title: string
          user_id: string
        }
        Update: {
          app_name?: string
          author_uid?: string | null
          chart?: Json | null
          created_at?: string
          id?: string
          kind?: string
          note?: string | null
          seen_at?: string | null
          title?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_sleep_sessions: {
        Row: {
          awake_seconds: number
          client_id: string
          created_at: string
          deep_seconds: number
          duration_seconds: number
          ended_at: string
          hrv_ms: number | null
          id: string
          light_seconds: number
          quality_score: number | null
          rem_seconds: number
          resting_hr_bpm: number | null
          source: string | null
          spo2_pct: number | null
          started_at: string
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          awake_seconds?: number
          client_id: string
          created_at?: string
          deep_seconds?: number
          duration_seconds?: number
          ended_at: string
          hrv_ms?: number | null
          id?: string
          light_seconds?: number
          quality_score?: number | null
          rem_seconds?: number
          resting_hr_bpm?: number | null
          source?: string | null
          spo2_pct?: number | null
          started_at: string
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          awake_seconds?: number
          client_id?: string
          created_at?: string
          deep_seconds?: number
          duration_seconds?: number
          ended_at?: string
          hrv_ms?: number | null
          id?: string
          light_seconds?: number
          quality_score?: number | null
          rem_seconds?: number
          resting_hr_bpm?: number | null
          source?: string | null
          spo2_pct?: number | null
          started_at?: string
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_steps_daily: {
        Row: {
          client_id: string
          created_at: string
          distance_m: number
          id: string
          recorded_on: string
          source: string | null
          steps: number
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          created_at?: string
          distance_m?: number
          id?: string
          recorded_on: string
          source?: string | null
          steps?: number
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          distance_m?: number
          id?: string
          recorded_on?: string
          source?: string | null
          steps?: number
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_streaks: {
        Row: {
          client_id: string
          created_at: string
          current_streak: number
          habit_key: string
          id: string
          last_check_in: string | null
          longest_streak: number
          recorded_on: string
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          client_id: string
          created_at?: string
          current_streak?: number
          habit_key: string
          id?: string
          last_check_in?: string | null
          longest_streak?: number
          recorded_on?: string
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          current_streak?: number
          habit_key?: string
          id?: string
          last_check_in?: string | null
          longest_streak?: number
          recorded_on?: string
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_sync_state: {
        Row: {
          domain: string
          last_error: string | null
          last_local_change_at: string | null
          last_synced_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          domain: string
          last_error?: string | null
          last_local_change_at?: string | null
          last_synced_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          domain?: string
          last_error?: string | null
          last_local_change_at?: string | null
          last_synced_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_verified_subscriptions: {
        Row: {
          checked_at: string
          environment: string
          expires_at: string | null
          has_max: boolean
          product_id: string | null
          source: string
          user_id: string
        }
        Insert: {
          checked_at: string
          environment?: string
          expires_at?: string | null
          has_max?: boolean
          product_id?: string | null
          source?: string
          user_id: string
        }
        Update: {
          checked_at?: string
          environment?: string
          expires_at?: string | null
          has_max?: boolean
          product_id?: string | null
          source?: string
          user_id?: string
        }
        Relationships: []
      }
      jasper_water_intake: {
        Row: {
          amount_ml: number
          client_id: string
          created_at: string
          id: string
          logged_at: string
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          amount_ml?: number
          client_id: string
          created_at?: string
          id?: string
          logged_at: string
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          amount_ml?: number
          client_id?: string
          created_at?: string
          id?: string
          logged_at?: string
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      jasper_work_documents_v1: {
        Row: {
          data: Json
          id: string
          owner_id: string
        }
        Insert: {
          data: Json
          id: string
          owner_id: string
        }
        Update: {
          data?: Json
          id?: string
          owner_id?: string
        }
        Relationships: []
      }
      jasper_work_events_v1: {
        Row: {
          at: string
          entity_id: string | null
          event: string
          id: string
          owner_id: string
        }
        Insert: {
          at?: string
          entity_id?: string | null
          event: string
          id: string
          owner_id: string
        }
        Update: {
          at?: string
          entity_id?: string | null
          event?: string
          id?: string
          owner_id?: string
        }
        Relationships: []
      }
      jasper_work_goals_v1: {
        Row: {
          data: Json
          id: string
          owner_id: string
        }
        Insert: {
          data: Json
          id: string
          owner_id: string
        }
        Update: {
          data?: Json
          id?: string
          owner_id?: string
        }
        Relationships: []
      }
      jasper_work_ideas_v1: {
        Row: {
          data: Json
          id: string
          owner_id: string
        }
        Insert: {
          data: Json
          id: string
          owner_id: string
        }
        Update: {
          data?: Json
          id?: string
          owner_id?: string
        }
        Relationships: []
      }
      jasper_work_jobs_v1: {
        Row: {
          data: Json
          id: string
          owner_id: string
        }
        Insert: {
          data: Json
          id: string
          owner_id: string
        }
        Update: {
          data?: Json
          id?: string
          owner_id?: string
        }
        Relationships: []
      }
      jasper_work_posts_v1: {
        Row: {
          data: Json
          id: string
          owner_id: string
        }
        Insert: {
          data: Json
          id: string
          owner_id: string
        }
        Update: {
          data?: Json
          id?: string
          owner_id?: string
        }
        Relationships: []
      }
      jasper_work_receipts_v1: {
        Row: {
          fingerprint: string
          id: string
          owner_id: string
          revision: number
        }
        Insert: {
          fingerprint: string
          id: string
          owner_id: string
          revision: number
        }
        Update: {
          fingerprint?: string
          id?: string
          owner_id?: string
          revision?: number
        }
        Relationships: []
      }
      jasper_work_state_v1: {
        Row: {
          owner_id: string
          revision: number
          settings: Json
        }
        Insert: {
          owner_id: string
          revision?: number
          settings?: Json
        }
        Update: {
          owner_id?: string
          revision?: number
          settings?: Json
        }
        Relationships: []
      }
      jasper_workout_sets: {
        Row: {
          client_id: string
          created_at: string
          exercise_id: string | null
          exercise_name: string
          id: string
          is_complete: boolean
          performed_at: string
          reps: number
          rpe: number | null
          set_index: number
          superset_group: string | null
          updated_at: string
          user_id: string
          visibility: string
          weight_kg: number
          workout_id: string | null
        }
        Insert: {
          client_id: string
          created_at?: string
          exercise_id?: string | null
          exercise_name: string
          id?: string
          is_complete?: boolean
          performed_at: string
          reps?: number
          rpe?: number | null
          set_index?: number
          superset_group?: string | null
          updated_at?: string
          user_id: string
          visibility?: string
          weight_kg?: number
          workout_id?: string | null
        }
        Update: {
          client_id?: string
          created_at?: string
          exercise_id?: string | null
          exercise_name?: string
          id?: string
          is_complete?: boolean
          performed_at?: string
          reps?: number
          rpe?: number | null
          set_index?: number
          superset_group?: string | null
          updated_at?: string
          user_id?: string
          visibility?: string
          weight_kg?: number
          workout_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "jasper_workout_sets_workout_id_fkey"
            columns: ["workout_id"]
            isOneToOne: false
            referencedRelation: "jasper_workouts"
            referencedColumns: ["id"]
          },
        ]
      }
      jasper_workouts: {
        Row: {
          avg_heart_rate: number
          avg_oxygen_saturation: number
          calories_burned: number
          client_id: string
          completed_sets: number
          created_at: string
          custom_name: string | null
          day_name: string | null
          duration_seconds: number
          exercise_count: number
          exercises: Json | null
          focus: string | null
          heart_rate_timeline: Json | null
          id: string
          peak_heart_rate: number
          performed_at: string
          program_id: string | null
          summary: string | null
          total_reps: number
          total_sets: number
          total_volume_kg: number
          updated_at: string
          user_id: string
          user_rating: number
          visibility: string
        }
        Insert: {
          avg_heart_rate?: number
          avg_oxygen_saturation?: number
          calories_burned?: number
          client_id: string
          completed_sets?: number
          created_at?: string
          custom_name?: string | null
          day_name?: string | null
          duration_seconds?: number
          exercise_count?: number
          exercises?: Json | null
          focus?: string | null
          heart_rate_timeline?: Json | null
          id?: string
          peak_heart_rate?: number
          performed_at: string
          program_id?: string | null
          summary?: string | null
          total_reps?: number
          total_sets?: number
          total_volume_kg?: number
          updated_at?: string
          user_id: string
          user_rating?: number
          visibility?: string
        }
        Update: {
          avg_heart_rate?: number
          avg_oxygen_saturation?: number
          calories_burned?: number
          client_id?: string
          completed_sets?: number
          created_at?: string
          custom_name?: string | null
          day_name?: string | null
          duration_seconds?: number
          exercise_count?: number
          exercises?: Json | null
          focus?: string | null
          heart_rate_timeline?: Json | null
          id?: string
          peak_heart_rate?: number
          performed_at?: string
          program_id?: string | null
          summary?: string | null
          total_reps?: number
          total_sets?: number
          total_volume_kg?: number
          updated_at?: string
          user_id?: string
          user_rating?: number
          visibility?: string
        }
        Relationships: []
      }
      knot_background_grants: {
        Row: {
          direct_messages: boolean
          enabled: boolean
          expires_at: string
          generation: string
          groups: boolean
          meet_plans: boolean
          owner_id: string
          updated_at: string
        }
        Insert: {
          direct_messages?: boolean
          enabled?: boolean
          expires_at?: string
          generation?: string
          groups?: boolean
          meet_plans?: boolean
          owner_id: string
          updated_at?: string
        }
        Update: {
          direct_messages?: boolean
          enabled?: boolean
          expires_at?: string
          generation?: string
          groups?: boolean
          meet_plans?: boolean
          owner_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      leaderboard_entries: {
        Row: {
          active_minutes_week: number
          steps_week: number
          updated_at: string
          user_id: string
          username: string
          week_id: number
          workouts_week: number
        }
        Insert: {
          active_minutes_week?: number
          steps_week?: number
          updated_at?: string
          user_id: string
          username: string
          week_id: number
          workouts_week?: number
        }
        Update: {
          active_minutes_week?: number
          steps_week?: number
          updated_at?: string
          user_id?: string
          username?: string
          week_id?: number
          workouts_week?: number
        }
        Relationships: []
      }
      nutrition_logs: {
        Row: {
          calories: number | null
          carbs_g: number | null
          fat_g: number | null
          fiber_g: number | null
          food_name: string | null
          id: string
          logged_at: string
          meal_type: string | null
          protein_g: number | null
          source: string | null
          user_id: string
        }
        Insert: {
          calories?: number | null
          carbs_g?: number | null
          fat_g?: number | null
          fiber_g?: number | null
          food_name?: string | null
          id?: string
          logged_at?: string
          meal_type?: string | null
          protein_g?: number | null
          source?: string | null
          user_id: string
        }
        Update: {
          calories?: number | null
          carbs_g?: number | null
          fat_g?: number | null
          fiber_g?: number | null
          food_name?: string | null
          id?: string
          logged_at?: string
          meal_type?: string | null
          protein_g?: number | null
          source?: string | null
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          active_subscription_product_id: string | null
          activity_level: string | null
          age_band: string | null
          auth_provider: string | null
          avatar_url: string | null
          bio: string | null
          current_streak: number
          date_of_birth: string | null
          discoverable_by_phone: boolean
          display_name: string | null
          email: string | null
          family_name: string | null
          fitness_goal: string | null
          gender: string | null
          given_name: string | null
          has_completed_profile_setup: boolean | null
          height_inches: number | null
          helpful_report_count: number
          id: string
          is_admin: boolean
          is_adult_attested: boolean
          is_athlete: boolean
          is_blogger: boolean
          is_coach: boolean
          is_director: boolean
          is_liar: boolean
          is_moderator: boolean
          is_owner: boolean
          is_pro_user: boolean | null
          is_recruiter: boolean
          is_trusted_member: boolean
          is_verified: boolean
          join_date: string | null
          last_active_at: string | null
          last_app_version: string | null
          last_device_model: string | null
          last_os_version: string | null
          last_workout_at: string | null
          liar_reason: string | null
          locale: string | null
          longest_streak: number
          notifications_enabled: boolean | null
          onboarding_completed_at: string | null
          phone: string | null
          profile_image_url: string | null
          push_token: string | null
          referral_code: string | null
          referred_by: string | null
          streak_days: number
          streak_last_day: string | null
          subscription_expires_at: string | null
          subscription_platform: string | null
          subscription_started_at: string | null
          subscription_will_renew: boolean | null
          timezone: string | null
          total_app_opens: number
          total_volume_kg: number
          total_workouts: number
          updated_at: string
          username: string | null
          verified_athlete: boolean
          weight_lbs: number | null
        }
        Insert: {
          active_subscription_product_id?: string | null
          activity_level?: string | null
          age_band?: string | null
          auth_provider?: string | null
          avatar_url?: string | null
          bio?: string | null
          current_streak?: number
          date_of_birth?: string | null
          discoverable_by_phone?: boolean
          display_name?: string | null
          email?: string | null
          family_name?: string | null
          fitness_goal?: string | null
          gender?: string | null
          given_name?: string | null
          has_completed_profile_setup?: boolean | null
          height_inches?: number | null
          helpful_report_count?: number
          id: string
          is_admin?: boolean
          is_adult_attested?: boolean
          is_athlete?: boolean
          is_blogger?: boolean
          is_coach?: boolean
          is_director?: boolean
          is_liar?: boolean
          is_moderator?: boolean
          is_owner?: boolean
          is_pro_user?: boolean | null
          is_recruiter?: boolean
          is_trusted_member?: boolean
          is_verified?: boolean
          join_date?: string | null
          last_active_at?: string | null
          last_app_version?: string | null
          last_device_model?: string | null
          last_os_version?: string | null
          last_workout_at?: string | null
          liar_reason?: string | null
          locale?: string | null
          longest_streak?: number
          notifications_enabled?: boolean | null
          onboarding_completed_at?: string | null
          phone?: string | null
          profile_image_url?: string | null
          push_token?: string | null
          referral_code?: string | null
          referred_by?: string | null
          streak_days?: number
          streak_last_day?: string | null
          subscription_expires_at?: string | null
          subscription_platform?: string | null
          subscription_started_at?: string | null
          subscription_will_renew?: boolean | null
          timezone?: string | null
          total_app_opens?: number
          total_volume_kg?: number
          total_workouts?: number
          updated_at?: string
          username?: string | null
          verified_athlete?: boolean
          weight_lbs?: number | null
        }
        Update: {
          active_subscription_product_id?: string | null
          activity_level?: string | null
          age_band?: string | null
          auth_provider?: string | null
          avatar_url?: string | null
          bio?: string | null
          current_streak?: number
          date_of_birth?: string | null
          discoverable_by_phone?: boolean
          display_name?: string | null
          email?: string | null
          family_name?: string | null
          fitness_goal?: string | null
          gender?: string | null
          given_name?: string | null
          has_completed_profile_setup?: boolean | null
          height_inches?: number | null
          helpful_report_count?: number
          id?: string
          is_admin?: boolean
          is_adult_attested?: boolean
          is_athlete?: boolean
          is_blogger?: boolean
          is_coach?: boolean
          is_director?: boolean
          is_liar?: boolean
          is_moderator?: boolean
          is_owner?: boolean
          is_pro_user?: boolean | null
          is_recruiter?: boolean
          is_trusted_member?: boolean
          is_verified?: boolean
          join_date?: string | null
          last_active_at?: string | null
          last_app_version?: string | null
          last_device_model?: string | null
          last_os_version?: string | null
          last_workout_at?: string | null
          liar_reason?: string | null
          locale?: string | null
          longest_streak?: number
          notifications_enabled?: boolean | null
          onboarding_completed_at?: string | null
          phone?: string | null
          profile_image_url?: string | null
          push_token?: string | null
          referral_code?: string | null
          referred_by?: string | null
          streak_days?: number
          streak_last_day?: string | null
          subscription_expires_at?: string | null
          subscription_platform?: string | null
          subscription_started_at?: string | null
          subscription_will_renew?: boolean | null
          timezone?: string | null
          total_app_opens?: number
          total_volume_kg?: number
          total_workouts?: number
          updated_at?: string
          username?: string | null
          verified_athlete?: boolean
          weight_lbs?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "profiles_referred_by_fkey"
            columns: ["referred_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      race_participants: {
        Row: {
          average_pace: number | null
          bib_number: number | null
          created_at: string | null
          display_name: string
          finish_time_seconds: number | null
          id: string
          race_id: string
          role: string
          status: string
        }
        Insert: {
          average_pace?: number | null
          bib_number?: number | null
          created_at?: string | null
          display_name: string
          finish_time_seconds?: number | null
          id: string
          race_id: string
          role?: string
          status?: string
        }
        Update: {
          average_pace?: number | null
          bib_number?: number | null
          created_at?: string | null
          display_name?: string
          finish_time_seconds?: number | null
          id?: string
          race_id?: string
          role?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "race_participants_race_id_fkey"
            columns: ["race_id"]
            isOneToOne: false
            referencedRelation: "races"
            referencedColumns: ["id"]
          },
        ]
      }
      races: {
        Row: {
          created_at: string | null
          distance: number
          finish_latitude: number | null
          finish_longitude: number | null
          id: string
          join_code: string
          name: string
          organizer_name: string
          race_started_at: string | null
          start_date: string
          start_latitude: number | null
          start_longitude: number | null
          status: string
        }
        Insert: {
          created_at?: string | null
          distance: number
          finish_latitude?: number | null
          finish_longitude?: number | null
          id: string
          join_code: string
          name: string
          organizer_name: string
          race_started_at?: string | null
          start_date: string
          start_latitude?: number | null
          start_longitude?: number | null
          status?: string
        }
        Update: {
          created_at?: string | null
          distance?: number
          finish_latitude?: number | null
          finish_longitude?: number | null
          id?: string
          join_code?: string
          name?: string
          organizer_name?: string
          race_started_at?: string | null
          start_date?: string
          start_latitude?: number | null
          start_longitude?: number | null
          status?: string
        }
        Relationships: []
      }
      runner_positions: {
        Row: {
          display_name: string
          distance_covered: number
          latitude: number
          longitude: number
          participant_id: string
          race_id: string
          speed: number
          timestamp: number
        }
        Insert: {
          display_name: string
          distance_covered?: number
          latitude?: number
          longitude?: number
          participant_id: string
          race_id: string
          speed?: number
          timestamp?: number
        }
        Update: {
          display_name?: string
          distance_covered?: number
          latitude?: number
          longitude?: number
          participant_id?: string
          race_id?: string
          speed?: number
          timestamp?: number
        }
        Relationships: []
      }
      subscription_events: {
        Row: {
          environment: string | null
          event_type: string
          expires_at: string | null
          id: number
          occurred_at: string
          original_transaction_id: string | null
          product_id: string
          raw_payload: Json | null
          transaction_id: string | null
          user_id: string
        }
        Insert: {
          environment?: string | null
          event_type: string
          expires_at?: string | null
          id?: number
          occurred_at?: string
          original_transaction_id?: string | null
          product_id: string
          raw_payload?: Json | null
          transaction_id?: string | null
          user_id: string
        }
        Update: {
          environment?: string | null
          event_type?: string
          expires_at?: string | null
          id?: number
          occurred_at?: string
          original_transaction_id?: string | null
          product_id?: string
          raw_payload?: Json | null
          transaction_id?: string | null
          user_id?: string
        }
        Relationships: []
      }
      user_data: {
        Row: {
          data_blob: string | null
          data_key: string
          updated_at: string
          user_id: string
        }
        Insert: {
          data_blob?: string | null
          data_key: string
          updated_at?: string
          user_id: string
        }
        Update: {
          data_blob?: string | null
          data_key?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_devices: {
        Row: {
          app_version: string | null
          device_id: string
          device_name: string | null
          id: string
          last_seen_at: string
          locale: string | null
          model: string | null
          os_version: string | null
          push_token: string | null
          timezone: string | null
          user_id: string
        }
        Insert: {
          app_version?: string | null
          device_id: string
          device_name?: string | null
          id?: string
          last_seen_at?: string
          locale?: string | null
          model?: string | null
          os_version?: string | null
          push_token?: string | null
          timezone?: string | null
          user_id: string
        }
        Update: {
          app_version?: string | null
          device_id?: string
          device_name?: string | null
          id?: string
          last_seen_at?: string
          locale?: string | null
          model?: string | null
          os_version?: string | null
          push_token?: string | null
          timezone?: string | null
          user_id?: string
        }
        Relationships: []
      }
      user_events: {
        Row: {
          app_version: string | null
          category: string | null
          device: string | null
          event: string
          id: number
          occurred_at: string
          os_version: string | null
          properties: Json
          timezone: string | null
          user_id: string
        }
        Insert: {
          app_version?: string | null
          category?: string | null
          device?: string | null
          event: string
          id?: number
          occurred_at?: string
          os_version?: string | null
          properties?: Json
          timezone?: string | null
          user_id: string
        }
        Update: {
          app_version?: string | null
          category?: string | null
          device?: string | null
          event?: string
          id?: number
          occurred_at?: string
          os_version?: string | null
          properties?: Json
          timezone?: string | null
          user_id?: string
        }
        Relationships: []
      }
      user_flags: {
        Row: {
          flag_key: string
          flag_value: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          flag_key: string
          flag_value?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          flag_key?: string
          flag_value?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      usernames: {
        Row: {
          created_at: string
          is_admin: boolean
          user_id: string
          username: string
        }
        Insert: {
          created_at?: string
          is_admin?: boolean
          user_id: string
          username: string
        }
        Update: {
          created_at?: string
          is_admin?: boolean
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_activity_state: {
        Row: {
          last_read_at: string
          user_id: string
        }
        Insert: {
          last_read_at?: string
          user_id: string
        }
        Update: {
          last_read_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_ad_autorecharge: {
        Row: {
          amount_cents: number
          enabled: boolean
          last_charged_at: string | null
          pending_session_id: string | null
          pm_brand: string | null
          pm_last4: string | null
          stripe_customer_id: string | null
          stripe_pm_id: string | null
          threshold_cents: number
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_cents?: number
          enabled?: boolean
          last_charged_at?: string | null
          pending_session_id?: string | null
          pm_brand?: string | null
          pm_last4?: string | null
          stripe_customer_id?: string | null
          stripe_pm_id?: string | null
          threshold_cents?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_cents?: number
          enabled?: boolean
          last_charged_at?: string | null
          pending_session_id?: string | null
          pm_brand?: string | null
          pm_last4?: string | null
          stripe_customer_id?: string | null
          stripe_pm_id?: string | null
          threshold_cents?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_ad_topups: {
        Row: {
          amount_cents: number
          created_at: string
          id: string
          source: string
          stripe_session_id: string | null
          user_id: string
        }
        Insert: {
          amount_cents: number
          created_at?: string
          id?: string
          source?: string
          stripe_session_id?: string | null
          user_id: string
        }
        Update: {
          amount_cents?: number
          created_at?: string
          id?: string
          source?: string
          stripe_session_id?: string | null
          user_id?: string
        }
        Relationships: []
      }
      whisper_admins: {
        Row: {
          created_at: string
          email: string | null
          id: string
          role: Database["public"]["Enums"]["whisper_admin_role"]
          user_id: string
          username: string | null
        }
        Insert: {
          created_at?: string
          email?: string | null
          id?: string
          role?: Database["public"]["Enums"]["whisper_admin_role"]
          user_id: string
          username?: string | null
        }
        Update: {
          created_at?: string
          email?: string | null
          id?: string
          role?: Database["public"]["Enums"]["whisper_admin_role"]
          user_id?: string
          username?: string | null
        }
        Relationships: []
      }
      whisper_applicant_notes: {
        Row: {
          created_at: string
          id: string
          note: string
          question_id: string
          recruiter_id: string
          response_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          note: string
          question_id: string
          recruiter_id: string
          response_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          note?: string
          question_id?: string
          recruiter_id?: string
          response_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_applicant_notes_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "whisper_applicant_questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whisper_applicant_notes_response_id_fkey"
            columns: ["response_id"]
            isOneToOne: false
            referencedRelation: "whisper_applicant_responses"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_applicant_questions: {
        Row: {
          created_at: string
          created_by: string | null
          display_order: number
          id: string
          is_active: boolean
          options: Json | null
          question: string
          question_type: string
          required: boolean
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          options?: Json | null
          question: string
          question_type?: string
          required?: boolean
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          options?: Json | null
          question?: string
          question_type?: string
          required?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      whisper_applicant_responses: {
        Row: {
          answers: Json
          applicant_email: string | null
          applicant_name: string | null
          applicant_user_id: string | null
          best_position: string | null
          confidence_score: number | null
          created_at: string
          id: string
          position_scores: Json | null
          potential_score: number | null
          recruiter_code: string | null
          recruiter_id: string
          status: string
          updated_at: string
        }
        Insert: {
          answers?: Json
          applicant_email?: string | null
          applicant_name?: string | null
          applicant_user_id?: string | null
          best_position?: string | null
          confidence_score?: number | null
          created_at?: string
          id?: string
          position_scores?: Json | null
          potential_score?: number | null
          recruiter_code?: string | null
          recruiter_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          answers?: Json
          applicant_email?: string | null
          applicant_name?: string | null
          applicant_user_id?: string | null
          best_position?: string | null
          confidence_score?: number | null
          created_at?: string
          id?: string
          position_scores?: Json | null
          potential_score?: number | null
          recruiter_code?: string | null
          recruiter_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      whisper_articles: {
        Row: {
          author_name: string
          author_user_id: string | null
          author_username: string | null
          category: string
          clip_time_seconds: number | null
          cover_url: string
          created_at: string
          excerpt: string
          film_id: string | null
          id: string
          paragraphs: Json
          published: boolean
          published_at: string
          slug: string
          title: string
          updated_at: string
        }
        Insert: {
          author_name?: string
          author_user_id?: string | null
          author_username?: string | null
          category?: string
          clip_time_seconds?: number | null
          cover_url?: string
          created_at?: string
          excerpt?: string
          film_id?: string | null
          id?: string
          paragraphs?: Json
          published?: boolean
          published_at?: string
          slug: string
          title: string
          updated_at?: string
        }
        Update: {
          author_name?: string
          author_user_id?: string | null
          author_username?: string | null
          category?: string
          clip_time_seconds?: number | null
          cover_url?: string
          created_at?: string
          excerpt?: string
          film_id?: string | null
          id?: string
          paragraphs?: Json
          published?: boolean
          published_at?: string
          slug?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_articles_film_id_fkey"
            columns: ["film_id"]
            isOneToOne: false
            referencedRelation: "whisper_films"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_athlete_applications: {
        Row: {
          bio: string
          created_at: string
          email: string | null
          full_name: string
          id: string
          level: string
          prs: string
          social: string | null
          sport: string
          status: Database["public"]["Enums"]["whisper_application_status"]
          team: string
          user_id: string
          username: string
        }
        Insert: {
          bio?: string
          created_at?: string
          email?: string | null
          full_name: string
          id?: string
          level?: string
          prs?: string
          social?: string | null
          sport?: string
          status?: Database["public"]["Enums"]["whisper_application_status"]
          team?: string
          user_id: string
          username: string
        }
        Update: {
          bio?: string
          created_at?: string
          email?: string | null
          full_name?: string
          id?: string
          level?: string
          prs?: string
          social?: string | null
          sport?: string
          status?: Database["public"]["Enums"]["whisper_application_status"]
          team?: string
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_athlete_meets: {
        Row: {
          created_at: string
          id: string
          location: string
          starts_at: string
          title: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          location?: string
          starts_at: string
          title: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          location?: string
          starts_at?: string
          title?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_athlete_prs: {
        Row: {
          achieved_on: string | null
          created_at: string
          id: string
          lift: string
          sort_order: number
          units: string
          user_id: string
          value: string
        }
        Insert: {
          achieved_on?: string | null
          created_at?: string
          id?: string
          lift: string
          sort_order?: number
          units?: string
          user_id: string
          value: string
        }
        Update: {
          achieved_on?: string | null
          created_at?: string
          id?: string
          lift?: string
          sort_order?: number
          units?: string
          user_id?: string
          value?: string
        }
        Relationships: []
      }
      whisper_badge_members: {
        Row: {
          created_at: string
          email: string | null
          id: string
          plan: string
          role: string
          status: string
          stripe_customer_id: string | null
          stripe_subscription_id: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          email?: string | null
          id?: string
          plan: string
          role: string
          status?: string
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          email?: string | null
          id?: string
          plan?: string
          role?: string
          status?: string
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      whisper_blind_date_decisions: {
        Row: {
          created_at: string
          decision: string
          room_code: string
          user_id: string
        }
        Insert: {
          created_at?: string
          decision: string
          room_code: string
          user_id: string
        }
        Update: {
          created_at?: string
          decision?: string
          room_code?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_blind_dates: {
        Row: {
          created_at: string
          ended_at: string | null
          guest_id: string | null
          host_id: string
          id: string
          recap: Json | null
          revealed: boolean
          room_code: string
          source: string
          started_at: string
        }
        Insert: {
          created_at?: string
          ended_at?: string | null
          guest_id?: string | null
          host_id: string
          id?: string
          recap?: Json | null
          revealed?: boolean
          room_code: string
          source?: string
          started_at?: string
        }
        Update: {
          created_at?: string
          ended_at?: string | null
          guest_id?: string | null
          host_id?: string
          id?: string
          recap?: Json | null
          revealed?: boolean
          room_code?: string
          source?: string
          started_at?: string
        }
        Relationships: []
      }
      whisper_blind_queue: {
        Row: {
          answers: Json
          joined_at: string
          last_seen: string
          paired_at: string | null
          partner_id: string | null
          partner_username: string | null
          role: string | null
          room_code: string | null
          status: string
          user_id: string
          username: string
        }
        Insert: {
          answers?: Json
          joined_at?: string
          last_seen?: string
          paired_at?: string | null
          partner_id?: string | null
          partner_username?: string | null
          role?: string | null
          room_code?: string | null
          status?: string
          user_id: string
          username?: string
        }
        Update: {
          answers?: Json
          joined_at?: string
          last_seen?: string
          paired_at?: string | null
          partner_id?: string | null
          partner_username?: string | null
          role?: string | null
          room_code?: string | null
          status?: string
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_blocks: {
        Row: {
          blocked_user_id: string
          blocked_username: string
          blocker_id: string
          created_at: string
          id: string
        }
        Insert: {
          blocked_user_id: string
          blocked_username: string
          blocker_id: string
          created_at?: string
          id?: string
        }
        Update: {
          blocked_user_id?: string
          blocked_username?: string
          blocker_id?: string
          created_at?: string
          id?: string
        }
        Relationships: []
      }
      whisper_bookmarks: {
        Row: {
          created_at: string
          post_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          post_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_bookmarks_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "whisper_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_bot_config: {
        Row: {
          id: number
          intensity: string
          last_run_at: string | null
          paused: boolean
          updated_at: string
        }
        Insert: {
          id?: number
          intensity?: string
          last_run_at?: string | null
          paused?: boolean
          updated_at?: string
        }
        Update: {
          id?: number
          intensity?: string
          last_run_at?: string | null
          paused?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      whisper_bots: {
        Row: {
          created_at: string
          persona: string
          user_id: string
          username: string
        }
        Insert: {
          created_at?: string
          persona: string
          user_id: string
          username: string
        }
        Update: {
          created_at?: string
          persona?: string
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_brand_profiles: {
        Row: {
          about: string | null
          amenities: string[]
          company_name: string
          cover_url: string | null
          created_at: string
          ember_checked_at: string | null
          ember_score: number | null
          ember_summary: string | null
          ember_verified: boolean
          industry: string | null
          instagram: string | null
          logo_url: string | null
          media_urls: string[]
          min_age: number
          min_followers: number
          min_posts: number
          pay_basis: string
          payment_terms: string | null
          published: boolean
          typical_pay_max_cents: number | null
          typical_pay_min_cents: number | null
          updated_at: string
          user_id: string
          username: string | null
          video_url: string | null
          website: string | null
        }
        Insert: {
          about?: string | null
          amenities?: string[]
          company_name: string
          cover_url?: string | null
          created_at?: string
          ember_checked_at?: string | null
          ember_score?: number | null
          ember_summary?: string | null
          ember_verified?: boolean
          industry?: string | null
          instagram?: string | null
          logo_url?: string | null
          media_urls?: string[]
          min_age?: number
          min_followers?: number
          min_posts?: number
          pay_basis?: string
          payment_terms?: string | null
          published?: boolean
          typical_pay_max_cents?: number | null
          typical_pay_min_cents?: number | null
          updated_at?: string
          user_id: string
          username?: string | null
          video_url?: string | null
          website?: string | null
        }
        Update: {
          about?: string | null
          amenities?: string[]
          company_name?: string
          cover_url?: string | null
          created_at?: string
          ember_checked_at?: string | null
          ember_score?: number | null
          ember_summary?: string | null
          ember_verified?: boolean
          industry?: string | null
          instagram?: string | null
          logo_url?: string | null
          media_urls?: string[]
          min_age?: number
          min_followers?: number
          min_posts?: number
          pay_basis?: string
          payment_terms?: string | null
          published?: boolean
          typical_pay_max_cents?: number | null
          typical_pay_min_cents?: number | null
          updated_at?: string
          user_id?: string
          username?: string | null
          video_url?: string | null
          website?: string | null
        }
        Relationships: []
      }
      whisper_business_applications: {
        Row: {
          answers: Json
          applicant_id: string
          applicant_username: string
          best_position: string | null
          business_id: string
          created_at: string
          id: string
          match_score: number
          position_scores: Json
          status: string
        }
        Insert: {
          answers?: Json
          applicant_id: string
          applicant_username?: string
          best_position?: string | null
          business_id: string
          created_at?: string
          id?: string
          match_score?: number
          position_scores?: Json
          status?: string
        }
        Update: {
          answers?: Json
          applicant_id?: string
          applicant_username?: string
          best_position?: string | null
          business_id?: string
          created_at?: string
          id?: string
          match_score?: number
          position_scores?: Json
          status?: string
        }
        Relationships: []
      }
      whisper_business_plus: {
        Row: {
          company_name: string | null
          created_at: string
          email: string | null
          id: string
          plan: string
          status: string
          stripe_customer_id: string | null
          stripe_subscription_id: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          company_name?: string | null
          created_at?: string
          email?: string | null
          id?: string
          plan?: string
          status?: string
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          company_name?: string | null
          created_at?: string
          email?: string | null
          id?: string
          plan?: string
          status?: string
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      whisper_business_positions: {
        Row: {
          blurb: string
          business_id: string
          created_at: string
          id: string
          is_open: boolean
          keywords: string[]
          title: string
        }
        Insert: {
          blurb?: string
          business_id: string
          created_at?: string
          id?: string
          is_open?: boolean
          keywords?: string[]
          title: string
        }
        Update: {
          blurb?: string
          business_id?: string
          created_at?: string
          id?: string
          is_open?: boolean
          keywords?: string[]
          title?: string
        }
        Relationships: []
      }
      whisper_business_questions: {
        Row: {
          business_id: string
          created_at: string
          display_order: number
          id: string
          is_active: boolean
          kind: string
          options: string[]
          prompt: string
        }
        Insert: {
          business_id: string
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          kind?: string
          options?: string[]
          prompt: string
        }
        Update: {
          business_id?: string
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          kind?: string
          options?: string[]
          prompt?: string
        }
        Relationships: []
      }
      whisper_business_team: {
        Row: {
          accent: string
          added_at: string
          business_id: string
          role_title: string
          user_id: string
          username: string
        }
        Insert: {
          accent?: string
          added_at?: string
          business_id: string
          role_title?: string
          user_id: string
          username?: string
        }
        Update: {
          accent?: string
          added_at?: string
          business_id?: string
          role_title?: string
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_calendar_events: {
        Row: {
          business_id: string | null
          created_at: string
          created_by: string
          created_by_username: string | null
          description: string | null
          end_time: string | null
          event_type: Database["public"]["Enums"]["whisper_calendar_event_type"]
          id: string
          location: string | null
          meeting_link: string | null
          recurrence: string
          recurrence_group: string | null
          start_time: string
          tagged_user_ids: string[]
          tagged_usernames: string[]
          title: string
        }
        Insert: {
          business_id?: string | null
          created_at?: string
          created_by: string
          created_by_username?: string | null
          description?: string | null
          end_time?: string | null
          event_type?: Database["public"]["Enums"]["whisper_calendar_event_type"]
          id?: string
          location?: string | null
          meeting_link?: string | null
          recurrence?: string
          recurrence_group?: string | null
          start_time: string
          tagged_user_ids?: string[]
          tagged_usernames?: string[]
          title: string
        }
        Update: {
          business_id?: string | null
          created_at?: string
          created_by?: string
          created_by_username?: string | null
          description?: string | null
          end_time?: string | null
          event_type?: Database["public"]["Enums"]["whisper_calendar_event_type"]
          id?: string
          location?: string | null
          meeting_link?: string | null
          recurrence?: string
          recurrence_group?: string | null
          start_time?: string
          tagged_user_ids?: string[]
          tagged_usernames?: string[]
          title?: string
        }
        Relationships: []
      }
      whisper_calendar_notes: {
        Row: {
          body: string
          created_at: string
          event_id: string
          id: string
          user_id: string
          username: string | null
        }
        Insert: {
          body: string
          created_at?: string
          event_id: string
          id?: string
          user_id: string
          username?: string | null
        }
        Update: {
          body?: string
          created_at?: string
          event_id?: string
          id?: string
          user_id?: string
          username?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "whisper_calendar_notes_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "whisper_calendar_events"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_calendar_reminders_sent: {
        Row: {
          event_id: string
          sent_at: string
        }
        Insert: {
          event_id: string
          sent_at?: string
        }
        Update: {
          event_id?: string
          sent_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_calendar_reminders_sent_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: true
            referencedRelation: "whisper_calendar_events"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_calendar_rsvps: {
        Row: {
          created_at: string
          event_id: string
          id: string
          status: string
          user_id: string
          username: string | null
        }
        Insert: {
          created_at?: string
          event_id: string
          id?: string
          status: string
          user_id: string
          username?: string | null
        }
        Update: {
          created_at?: string
          event_id?: string
          id?: string
          status?: string
          user_id?: string
          username?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "whisper_calendar_rsvps_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "whisper_calendar_events"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_call_push_dedupe: {
        Row: {
          call_id: string
          created_at: string
        }
        Insert: {
          call_id: string
          created_at?: string
        }
        Update: {
          call_id?: string
          created_at?: string
        }
        Relationships: []
      }
      whisper_client_snapshots: {
        Row: {
          payload: Json
          photo_back_url: string | null
          photo_front_url: string | null
          photo_side_url: string | null
          updated_at: string
          user_id: string
          username: string
        }
        Insert: {
          payload?: Json
          photo_back_url?: string | null
          photo_front_url?: string | null
          photo_side_url?: string | null
          updated_at?: string
          user_id: string
          username: string
        }
        Update: {
          payload?: Json
          photo_back_url?: string | null
          photo_front_url?: string | null
          photo_side_url?: string | null
          updated_at?: string
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_coach_applications: {
        Row: {
          bio: string
          created_at: string
          credentials: string
          email: string | null
          experience_years: number
          full_name: string
          id: string
          social: string | null
          specialties: string[]
          status: Database["public"]["Enums"]["whisper_application_status"]
          user_id: string
          username: string
          website: string | null
        }
        Insert: {
          bio?: string
          created_at?: string
          credentials?: string
          email?: string | null
          experience_years?: number
          full_name: string
          id?: string
          social?: string | null
          specialties?: string[]
          status?: Database["public"]["Enums"]["whisper_application_status"]
          user_id: string
          username: string
          website?: string | null
        }
        Update: {
          bio?: string
          created_at?: string
          credentials?: string
          email?: string | null
          experience_years?: number
          full_name?: string
          id?: string
          social?: string | null
          specialties?: string[]
          status?: Database["public"]["Enums"]["whisper_application_status"]
          user_id?: string
          username?: string
          website?: string | null
        }
        Relationships: []
      }
      whisper_coach_connect: {
        Row: {
          charges_enabled: boolean
          details_submitted: boolean
          payouts_enabled: boolean
          stripe_account_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          charges_enabled?: boolean
          details_submitted?: boolean
          payouts_enabled?: boolean
          stripe_account_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          charges_enabled?: boolean
          details_submitted?: boolean
          payouts_enabled?: boolean
          stripe_account_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_coach_earnings: {
        Row: {
          client_email: string | null
          client_user_id: string | null
          coach_user_id: string
          created_at: string
          description: string | null
          fee_cents: number
          gross_cents: number
          id: number
          net_cents: number
          refunded: boolean
          stripe_session_id: string | null
        }
        Insert: {
          client_email?: string | null
          client_user_id?: string | null
          coach_user_id: string
          created_at?: string
          description?: string | null
          fee_cents?: number
          gross_cents?: number
          id?: never
          net_cents?: number
          refunded?: boolean
          stripe_session_id?: string | null
        }
        Update: {
          client_email?: string | null
          client_user_id?: string | null
          coach_user_id?: string
          created_at?: string
          description?: string | null
          fee_cents?: number
          gross_cents?: number
          id?: never
          net_cents?: number
          refunded?: boolean
          stripe_session_id?: string | null
        }
        Relationships: []
      }
      whisper_coach_plans: {
        Row: {
          active: boolean
          coach_user_id: string
          created_at: string
          id: string
          max_clients: number | null
          monthly_price_cents: number
          name: string
          perks: Json
          sort: number
          tagline: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          coach_user_id: string
          created_at?: string
          id?: string
          max_clients?: number | null
          monthly_price_cents: number
          name: string
          perks?: Json
          sort?: number
          tagline?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          coach_user_id?: string
          created_at?: string
          id?: string
          max_clients?: number | null
          monthly_price_cents?: number
          name?: string
          perks?: Json
          sort?: number
          tagline?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      whisper_coach_pricing: {
        Row: {
          active: boolean
          monthly_price_cents: number
          updated_at: string
          user_id: string
        }
        Insert: {
          active?: boolean
          monthly_price_cents: number
          updated_at?: string
          user_id: string
        }
        Update: {
          active?: boolean
          monthly_price_cents?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_coach_programs: {
        Row: {
          coach_user_id: string
          coach_username: string
          created_at: string
          focus: string
          id: string
          is_public: boolean
          payload: Json
          sessions_per_week: number
          summary: string
          title: string
          weeks: number
        }
        Insert: {
          coach_user_id: string
          coach_username: string
          created_at?: string
          focus?: string
          id: string
          is_public?: boolean
          payload: Json
          sessions_per_week?: number
          summary?: string
          title: string
          weeks?: number
        }
        Update: {
          coach_user_id?: string
          coach_username?: string
          created_at?: string
          focus?: string
          id?: string
          is_public?: boolean
          payload?: Json
          sessions_per_week?: number
          summary?: string
          title?: string
          weeks?: number
        }
        Relationships: []
      }
      whisper_coach_proposals: {
        Row: {
          client_user_id: string
          coach_user_id: string
          coach_username: string | null
          created_at: string
          expires_at: string | null
          id: string
          kind: string
          note: string | null
          patch: Json
          responded_at: string | null
          status: string
          target_id: string | null
          updated_at: string
        }
        Insert: {
          client_user_id: string
          coach_user_id: string
          coach_username?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          kind: string
          note?: string | null
          patch?: Json
          responded_at?: string | null
          status?: string
          target_id?: string | null
          updated_at?: string
        }
        Update: {
          client_user_id?: string
          coach_user_id?: string
          coach_username?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          kind?: string
          note?: string | null
          patch?: Json
          responded_at?: string | null
          status?: string
          target_id?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      whisper_coach_requests: {
        Row: {
          client_user_id: string
          client_username: string
          coach_user_id: string
          coach_username: string
          created_at: string
          id: string
          message: string
          status: string
          updated_at: string
        }
        Insert: {
          client_user_id: string
          client_username: string
          coach_user_id: string
          coach_username: string
          created_at?: string
          id?: string
          message?: string
          status?: string
          updated_at?: string
        }
        Update: {
          client_user_id?: string
          client_username?: string
          coach_user_id?: string
          coach_username?: string
          created_at?: string
          id?: string
          message?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      whisper_collab_activities: {
        Row: {
          created_at: string
          created_by: string
          created_by_username: string
          detail: string
          due_on: string | null
          id: string
          kind: string
          project_id: string
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          created_by_username?: string
          detail?: string
          due_on?: string | null
          id?: string
          kind?: string
          project_id: string
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          created_by_username?: string
          detail?: string
          due_on?: string | null
          id?: string
          kind?: string
          project_id?: string
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_collab_activities_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "whisper_collab_projects"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_collab_members: {
        Row: {
          created_at: string
          invited_by: string
          project_id: string
          role: string
          status: string
          user_id: string
          username: string
        }
        Insert: {
          created_at?: string
          invited_by: string
          project_id: string
          role?: string
          status?: string
          user_id: string
          username?: string
        }
        Update: {
          created_at?: string
          invited_by?: string
          project_id?: string
          role?: string
          status?: string
          user_id?: string
          username?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_collab_members_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "whisper_collab_projects"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_collab_projects: {
        Row: {
          created_at: string
          created_by: string
          created_by_username: string
          format: string
          id: string
          status: string
          summary: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          created_by_username?: string
          format?: string
          id?: string
          status?: string
          summary?: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          created_by_username?: string
          format?: string
          id?: string
          status?: string
          summary?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      whisper_comment_likes: {
        Row: {
          comment_id: string
          created_at: string
          user_id: string
        }
        Insert: {
          comment_id: string
          created_at?: string
          user_id: string
        }
        Update: {
          comment_id?: string
          created_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_comment_likes_comment_id_fkey"
            columns: ["comment_id"]
            isOneToOne: false
            referencedRelation: "whisper_post_comments"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_comments: {
        Row: {
          body: string
          created_at: string
          id: string
          post_id: string
          user_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          post_id: string
          user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "whisper_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_communities: {
        Row: {
          color1: string
          color2: string
          created_at: string
          creator_id: string | null
          creator_username: string
          id: string
          keywords: string[]
          name: string
          slug: string
          tagline: string
          visibility: string
        }
        Insert: {
          color1?: string
          color2?: string
          created_at?: string
          creator_id?: string | null
          creator_username?: string
          id?: string
          keywords?: string[]
          name: string
          slug: string
          tagline?: string
          visibility?: string
        }
        Update: {
          color1?: string
          color2?: string
          created_at?: string
          creator_id?: string | null
          creator_username?: string
          id?: string
          keywords?: string[]
          name?: string
          slug?: string
          tagline?: string
          visibility?: string
        }
        Relationships: []
      }
      whisper_community_members: {
        Row: {
          community_slug: string
          created_at: string
          invited_by: string
          role: string
          status: string
          user_id: string
          username: string
        }
        Insert: {
          community_slug: string
          created_at?: string
          invited_by?: string
          role?: string
          status?: string
          user_id: string
          username?: string
        }
        Update: {
          community_slug?: string
          created_at?: string
          invited_by?: string
          role?: string
          status?: string
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_contact_identities: {
        Row: {
          created_at: string
          hash: string
          kind: string
          user_id: string
        }
        Insert: {
          created_at?: string
          hash: string
          kind?: string
          user_id: string
        }
        Update: {
          created_at?: string
          hash?: string
          kind?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_contact_permissions: {
        Row: {
          allowed: boolean
          recipient_id: string
          sender_id: string
          updated_at: string
        }
        Insert: {
          allowed?: boolean
          recipient_id: string
          sender_id: string
          updated_at?: string
        }
        Update: {
          allowed?: boolean
          recipient_id?: string
          sender_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      whisper_contact_restrictions: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          reason: string
          review_at: string
          reviewed_by: string
          revoked_at: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          expires_at: string
          id?: string
          reason: string
          review_at: string
          reviewed_by: string
          revoked_at?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          reason?: string
          review_at?: string
          reviewed_by?: string
          revoked_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      whisper_correction_appeals: {
        Row: {
          author_id: string
          body: string
          correction_id: string
          created_at: string
          id: string
          outcome: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        Insert: {
          author_id: string
          body: string
          correction_id: string
          created_at?: string
          id?: string
          outcome?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
        }
        Update: {
          author_id?: string
          body?: string
          correction_id?: string
          created_at?: string
          id?: string
          outcome?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_correction_appeals_correction_id_fkey"
            columns: ["correction_id"]
            isOneToOne: true
            referencedRelation: "whisper_corrections"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_correction_history: {
        Row: {
          action: string
          actor_id: string
          correction_id: string
          created_at: string
          explanation: string
          id: string
          sources: string[]
        }
        Insert: {
          action: string
          actor_id: string
          correction_id: string
          created_at?: string
          explanation: string
          id?: string
          sources: string[]
        }
        Update: {
          action?: string
          actor_id?: string
          correction_id?: string
          created_at?: string
          explanation?: string
          id?: string
          sources?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "whisper_correction_history_correction_id_fkey"
            columns: ["correction_id"]
            isOneToOne: false
            referencedRelation: "whisper_corrections"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_corrections: {
        Row: {
          author_id: string
          created_at: string
          explanation: string
          id: string
          post_id: string
          report_id: string
          reviewed_by: string
          reviewed_snapshot: Json
          sources: string[]
          state: string
          updated_at: string
        }
        Insert: {
          author_id: string
          created_at?: string
          explanation: string
          id?: string
          post_id: string
          report_id: string
          reviewed_by: string
          reviewed_snapshot: Json
          sources: string[]
          state?: string
          updated_at?: string
        }
        Update: {
          author_id?: string
          created_at?: string
          explanation?: string
          id?: string
          post_id?: string
          report_id?: string
          reviewed_by?: string
          reviewed_snapshot?: Json
          sources?: string[]
          state?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_corrections_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: true
            referencedRelation: "whisper_reports"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_dating_event_rsvps: {
        Row: {
          created_at: string
          event_key: string
          user_id: string
          username: string
        }
        Insert: {
          created_at?: string
          event_key: string
          user_id: string
          username?: string
        }
        Update: {
          created_at?: string
          event_key?: string
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_dating_intros: {
        Row: {
          created_at: string
          duration_s: number
          kind: string
          url: string
          user_id: string
          username: string | null
        }
        Insert: {
          created_at?: string
          duration_s?: number
          kind?: string
          url: string
          user_id: string
          username?: string | null
        }
        Update: {
          created_at?: string
          duration_s?: number
          kind?: string
          url?: string
          user_id?: string
          username?: string | null
        }
        Relationships: []
      }
      whisper_dating_prefs: {
        Row: {
          age: number | null
          age_max: number
          age_min: number
          city_label: string | null
          dealbreakers: Json
          gender: string | null
          intent: string | null
          lat: number | null
          lifestyle: Json
          lng: number | null
          radius_km: number
          seeking: string[]
          updated_at: string
          user_id: string
          username: string | null
        }
        Insert: {
          age?: number | null
          age_max?: number
          age_min?: number
          city_label?: string | null
          dealbreakers?: Json
          gender?: string | null
          intent?: string | null
          lat?: number | null
          lifestyle?: Json
          lng?: number | null
          radius_km?: number
          seeking?: string[]
          updated_at?: string
          user_id: string
          username?: string | null
        }
        Update: {
          age?: number | null
          age_max?: number
          age_min?: number
          city_label?: string | null
          dealbreakers?: Json
          gender?: string | null
          intent?: string | null
          lat?: number | null
          lifestyle?: Json
          lng?: number | null
          radius_km?: number
          seeking?: string[]
          updated_at?: string
          user_id?: string
          username?: string | null
        }
        Relationships: []
      }
      whisper_dating_reports: {
        Row: {
          created_at: string
          details: string | null
          id: string
          reason: string
          reported_id: string | null
          reported_username: string
          reporter_id: string
          room_code: string | null
        }
        Insert: {
          created_at?: string
          details?: string | null
          id?: string
          reason: string
          reported_id?: string | null
          reported_username: string
          reporter_id: string
          room_code?: string | null
        }
        Update: {
          created_at?: string
          details?: string | null
          id?: string
          reason?: string
          reported_id?: string | null
          reported_username?: string
          reporter_id?: string
          room_code?: string | null
        }
        Relationships: []
      }
      whisper_dating_verifications: {
        Row: {
          created_at: string
          method: string
          reviewed_at: string | null
          reviewed_by: string | null
          selfie_url: string | null
          status: string
          user_id: string
          username: string | null
        }
        Insert: {
          created_at?: string
          method?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          selfie_url?: string | null
          status?: string
          user_id: string
          username?: string | null
        }
        Update: {
          created_at?: string
          method?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          selfie_url?: string | null
          status?: string
          user_id?: string
          username?: string | null
        }
        Relationships: []
      }
      whisper_device_tokens: {
        Row: {
          active: boolean
          bundle_id: string | null
          created_at: string
          environment: string
          platform: string
          sandbox: boolean | null
          token: string
          updated_at: string
          user_id: string
        }
        Insert: {
          active?: boolean
          bundle_id?: string | null
          created_at?: string
          environment?: string
          platform?: string
          sandbox?: boolean | null
          token: string
          updated_at?: string
          user_id: string
        }
        Update: {
          active?: boolean
          bundle_id?: string | null
          created_at?: string
          environment?: string
          platform?: string
          sandbox?: boolean | null
          token?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_disappearing_job: {
        Row: {
          id: number
          secret: string
        }
        Insert: {
          id: number
          secret?: string
        }
        Update: {
          id?: number
          secret?: string
        }
        Relationships: []
      }
      whisper_disappearing_media: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          mime: string
          object_path: string
          opened_at: string | null
          purged: boolean
          ready: boolean
          recipient_id: string
          sender_id: string
        }
        Insert: {
          created_at?: string
          expires_at?: string
          id: string
          mime: string
          object_path: string
          opened_at?: string | null
          purged?: boolean
          ready?: boolean
          recipient_id: string
          sender_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          mime?: string
          object_path?: string
          opened_at?: string | null
          purged?: boolean
          ready?: boolean
          recipient_id?: string
          sender_id?: string
        }
        Relationships: []
      }
      whisper_disappearing_purge_queue: {
        Row: {
          created_at: string
          object_path: string
        }
        Insert: {
          created_at?: string
          object_path: string
        }
        Update: {
          created_at?: string
          object_path?: string
        }
        Relationships: []
      }
      whisper_dm_blocks: {
        Row: {
          blocked_sender_id: string
          created_at: string
          id: string
          protected_user_id: string
          reason: string | null
        }
        Insert: {
          blocked_sender_id: string
          created_at?: string
          id?: string
          protected_user_id: string
          reason?: string | null
        }
        Update: {
          blocked_sender_id?: string
          created_at?: string
          id?: string
          protected_user_id?: string
          reason?: string | null
        }
        Relationships: []
      }
      whisper_document_comments: {
        Row: {
          anchor: Json | null
          author_id: string
          body: string
          created_at: string
          document_id: string
          id: string
          parent_id: string | null
          quote: string
          resolved: boolean
        }
        Insert: {
          anchor?: Json | null
          author_id: string
          body: string
          created_at?: string
          document_id: string
          id: string
          parent_id?: string | null
          quote?: string
          resolved?: boolean
        }
        Update: {
          anchor?: Json | null
          author_id?: string
          body?: string
          created_at?: string
          document_id?: string
          id?: string
          parent_id?: string | null
          quote?: string
          resolved?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "whisper_document_comments_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "whisper_shared_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_document_members: {
        Row: {
          created_at: string
          document_id: string
          email: string | null
          id: string
          invited_by: string
          last_email_at: string | null
          role: string
          status: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          document_id: string
          email?: string | null
          id: string
          invited_by: string
          last_email_at?: string | null
          role: string
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          document_id?: string
          email?: string | null
          id?: string
          invited_by?: string
          last_email_at?: string | null
          role?: string
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "whisper_document_members_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "whisper_shared_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_document_presence: {
        Row: {
          document_id: string
          selection: Json | null
          session_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          document_id: string
          selection?: Json | null
          session_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          document_id?: string
          selection?: Json | null
          session_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_document_presence_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "whisper_shared_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_document_suggestions: {
        Row: {
          anchor: Json
          author_id: string
          created_at: string
          decided_at: string | null
          decided_by: string | null
          document_id: string
          id: string
          operation_id: string | null
          quote: string
          replacement: string
          status: string
        }
        Insert: {
          anchor: Json
          author_id: string
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          document_id: string
          id: string
          operation_id?: string | null
          quote: string
          replacement: string
          status?: string
        }
        Update: {
          anchor?: Json
          author_id?: string
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          document_id?: string
          id?: string
          operation_id?: string | null
          quote?: string
          replacement?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_document_suggestions_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "whisper_shared_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_document_updates: {
        Row: {
          author_id: string
          created_at: string
          document_id: string
          operation_id: string
          seq: number
          update_data: string
        }
        Insert: {
          author_id: string
          created_at?: string
          document_id: string
          operation_id: string
          seq: number
          update_data: string
        }
        Update: {
          author_id?: string
          created_at?: string
          document_id?: string
          operation_id?: string
          seq?: number
          update_data?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_document_updates_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "whisper_shared_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_document_versions: {
        Row: {
          author_id: string
          content: Json
          created_at: string
          document_id: string
          id: string
          label: string
          seq: number
        }
        Insert: {
          author_id: string
          content: Json
          created_at?: string
          document_id: string
          id: string
          label: string
          seq: number
        }
        Update: {
          author_id?: string
          content?: Json
          created_at?: string
          document_id?: string
          id?: string
          label?: string
          seq?: number
        }
        Relationships: [
          {
            foreignKeyName: "whisper_document_versions_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "whisper_shared_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_event_invites_v1: {
        Row: {
          created_at: string
          event_id: string
          guests: number
          id: string
          label: string
          message_id: string | null
          note: string
          recipient_id: string | null
          recipient_key: string
          responded_at: string | null
          response: string
          response_revision: number | null
          response_version: number
          revoked: boolean
          token: string
        }
        Insert: {
          created_at?: string
          event_id: string
          guests?: number
          id?: string
          label: string
          message_id?: string | null
          note?: string
          recipient_id?: string | null
          recipient_key: string
          responded_at?: string | null
          response?: string
          response_revision?: number | null
          response_version?: number
          revoked?: boolean
          token?: string
        }
        Update: {
          created_at?: string
          event_id?: string
          guests?: number
          id?: string
          label?: string
          message_id?: string | null
          note?: string
          recipient_id?: string | null
          recipient_key?: string
          responded_at?: string | null
          response?: string
          response_revision?: number | null
          response_version?: number
          revoked?: boolean
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_event_invites_v1_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "whisper_team_events_v1"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_events: {
        Row: {
          app_version: string | null
          created_at: string
          event: string
          id: string
          os_version: string | null
          props: Json | null
          session_id: string
          user_id: string | null
        }
        Insert: {
          app_version?: string | null
          created_at?: string
          event: string
          id?: string
          os_version?: string | null
          props?: Json | null
          session_id: string
          user_id?: string | null
        }
        Update: {
          app_version?: string | null
          created_at?: string
          event?: string
          id?: string
          os_version?: string | null
          props?: Json | null
          session_id?: string
          user_id?: string | null
        }
        Relationships: []
      }
      whisper_featured_links: {
        Row: {
          created_at: string
          emoji: string | null
          id: string
          position: number
          title: string
          url: string
          user_id: string
        }
        Insert: {
          created_at?: string
          emoji?: string | null
          id?: string
          position?: number
          title: string
          url: string
          user_id: string
        }
        Update: {
          created_at?: string
          emoji?: string | null
          id?: string
          position?: number
          title?: string
          url?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_featured_profiles: {
        Row: {
          action_buttons: Json
          age: string | null
          chips: Json
          created_at: string
          cta_label: string | null
          cta_url: string | null
          discipline: string | null
          highlights: Json
          id: string
          kind: string
          name: string
          paragraphs: Json
          photo_url: string
          published: boolean
          sort_order: number
          testimonials: Json
          tier: number | null
          updated_at: string
          user_id: string | null
          username: string | null
        }
        Insert: {
          action_buttons?: Json
          age?: string | null
          chips?: Json
          created_at?: string
          cta_label?: string | null
          cta_url?: string | null
          discipline?: string | null
          highlights?: Json
          id?: string
          kind: string
          name: string
          paragraphs?: Json
          photo_url?: string
          published?: boolean
          sort_order?: number
          testimonials?: Json
          tier?: number | null
          updated_at?: string
          user_id?: string | null
          username?: string | null
        }
        Update: {
          action_buttons?: Json
          age?: string | null
          chips?: Json
          created_at?: string
          cta_label?: string | null
          cta_url?: string | null
          discipline?: string | null
          highlights?: Json
          id?: string
          kind?: string
          name?: string
          paragraphs?: Json
          photo_url?: string
          published?: boolean
          sort_order?: number
          testimonials?: Json
          tier?: number | null
          updated_at?: string
          user_id?: string | null
          username?: string | null
        }
        Relationships: []
      }
      whisper_film_comments: {
        Row: {
          body: string
          created_at: string
          film_id: string
          id: string
          reply_to_comment_id: string | null
          user_id: string
        }
        Insert: {
          body: string
          created_at?: string
          film_id: string
          id?: string
          reply_to_comment_id?: string | null
          user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          film_id?: string
          id?: string
          reply_to_comment_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_film_comments_film_id_fkey"
            columns: ["film_id"]
            isOneToOne: false
            referencedRelation: "whisper_films"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whisper_film_comments_reply_to_comment_id_fkey"
            columns: ["reply_to_comment_id"]
            isOneToOne: false
            referencedRelation: "whisper_film_comments"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_film_reactions: {
        Row: {
          created_at: string
          film_id: string
          id: string
          user_id: string
          weight: string
        }
        Insert: {
          created_at?: string
          film_id: string
          id?: string
          user_id: string
          weight: string
        }
        Update: {
          created_at?: string
          film_id?: string
          id?: string
          user_id?: string
          weight?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_film_reactions_film_id_fkey"
            columns: ["film_id"]
            isOneToOne: false
            referencedRelation: "whisper_films"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_film_timestamps: {
        Row: {
          created_at: string
          film_id: string
          id: string
          label: string
          poster_url: string | null
          time_seconds: number
          user_id: string
        }
        Insert: {
          created_at?: string
          film_id: string
          id?: string
          label: string
          poster_url?: string | null
          time_seconds: number
          user_id: string
        }
        Update: {
          created_at?: string
          film_id?: string
          id?: string
          label?: string
          poster_url?: string | null
          time_seconds?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_film_timestamps_film_id_fkey"
            columns: ["film_id"]
            isOneToOne: false
            referencedRelation: "whisper_films"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_films: {
        Row: {
          created_at: string
          director_id: string
          duration_seconds: number | null
          featured_date: string | null
          id: string
          poster_url: string | null
          published: boolean
          synopsis: string | null
          title: string
          trailer_url: string | null
          updated_at: string
          video_url: string
        }
        Insert: {
          created_at?: string
          director_id: string
          duration_seconds?: number | null
          featured_date?: string | null
          id?: string
          poster_url?: string | null
          published?: boolean
          synopsis?: string | null
          title: string
          trailer_url?: string | null
          updated_at?: string
          video_url: string
        }
        Update: {
          created_at?: string
          director_id?: string
          duration_seconds?: number | null
          featured_date?: string | null
          id?: string
          poster_url?: string | null
          published?: boolean
          synopsis?: string | null
          title?: string
          trailer_url?: string | null
          updated_at?: string
          video_url?: string
        }
        Relationships: []
      }
      whisper_follow_requests: {
        Row: {
          created_at: string
          id: string
          requester_id: string
          requester_username: string
          responded_at: string | null
          status: string
          target_id: string
          target_username: string
        }
        Insert: {
          created_at?: string
          id?: string
          requester_id: string
          requester_username: string
          responded_at?: string | null
          status?: string
          target_id: string
          target_username: string
        }
        Update: {
          created_at?: string
          id?: string
          requester_id?: string
          requester_username?: string
          responded_at?: string | null
          status?: string
          target_id?: string
          target_username?: string
        }
        Relationships: []
      }
      whisper_follows: {
        Row: {
          created_at: string
          followee_id: string
          followee_username: string
          follower_id: string
        }
        Insert: {
          created_at?: string
          followee_id: string
          followee_username?: string
          follower_id: string
        }
        Update: {
          created_at?: string
          followee_id?: string
          followee_username?: string
          follower_id?: string
        }
        Relationships: []
      }
      whisper_gift_cashouts: {
        Row: {
          amount_cents: number
          created_at: string
          id: string
          user_id: string
        }
        Insert: {
          amount_cents: number
          created_at?: string
          id?: string
          user_id: string
        }
        Update: {
          amount_cents?: number
          created_at?: string
          id?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_gift_topups: {
        Row: {
          amount_cents: number
          created_at: string
          id: string
          stripe_session_id: string | null
          user_id: string
        }
        Insert: {
          amount_cents: number
          created_at?: string
          id?: string
          stripe_session_id?: string | null
          user_id: string
        }
        Update: {
          amount_cents?: number
          created_at?: string
          id?: string
          stripe_session_id?: string | null
          user_id?: string
        }
        Relationships: []
      }
      whisper_gift_wallets: {
        Row: {
          balance_cents: number
          updated_at: string
          user_id: string
        }
        Insert: {
          balance_cents?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          balance_cents?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_group_message_identity: {
        Row: {
          body: string
          created_at: string
          group_id: string
          id: string
          sender_id: string
        }
        Insert: {
          body: string
          created_at?: string
          group_id: string
          id: string
          sender_id: string
        }
        Update: {
          body?: string
          created_at?: string
          group_id?: string
          id?: string
          sender_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_group_message_identity_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "whisper_group_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_group_themes: {
        Row: {
          group_id: string
          operation_id: string
          revision: number
          theme: Json
          updated_at: string
          updated_by: string
        }
        Insert: {
          group_id: string
          operation_id: string
          revision?: number
          theme: Json
          updated_at?: string
          updated_by: string
        }
        Update: {
          group_id?: string
          operation_id?: string
          revision?: number
          theme?: Json
          updated_at?: string
          updated_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_group_themes_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: true
            referencedRelation: "whisper_group_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_group_threads: {
        Row: {
          avatar_path: string | null
          business_id: string | null
          created_at: string
          id: string
          member_ids: string[]
          member_usernames: string[]
          name: string
          owner_id: string
        }
        Insert: {
          avatar_path?: string | null
          business_id?: string | null
          created_at?: string
          id?: string
          member_ids?: string[]
          member_usernames?: string[]
          name: string
          owner_id: string
        }
        Update: {
          avatar_path?: string | null
          business_id?: string | null
          created_at?: string
          id?: string
          member_ids?: string[]
          member_usernames?: string[]
          name?: string
          owner_id?: string
        }
        Relationships: []
      }
      whisper_helpful_reports: {
        Row: {
          confirmed_by: string
          created_at: string
          id: string
          note: string | null
          reporter_user_id: string
          strike_id: string | null
          target_user_id: string | null
        }
        Insert: {
          confirmed_by: string
          created_at?: string
          id?: string
          note?: string | null
          reporter_user_id: string
          strike_id?: string | null
          target_user_id?: string | null
        }
        Update: {
          confirmed_by?: string
          created_at?: string
          id?: string
          note?: string | null
          reporter_user_id?: string
          strike_id?: string | null
          target_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "whisper_helpful_reports_strike_id_fkey"
            columns: ["strike_id"]
            isOneToOne: false
            referencedRelation: "whisper_safety_strikes"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_legacy_label_history: {
        Row: {
          archived_at: string
          reason: string | null
          source: string
          user_id: string
        }
        Insert: {
          archived_at?: string
          reason?: string | null
          source: string
          user_id: string
        }
        Update: {
          archived_at?: string
          reason?: string | null
          source?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_liar_appeals: {
        Row: {
          author_id: string | null
          body: string
          created_at: string
          id: string
          status: string
          username: string
        }
        Insert: {
          author_id?: string | null
          body: string
          created_at?: string
          id?: string
          status?: string
          username: string
        }
        Update: {
          author_id?: string | null
          body?: string
          created_at?: string
          id?: string
          status?: string
          username?: string
        }
        Relationships: []
      }
      whisper_liar_badges: {
        Row: {
          acknowledged_at: string | null
          appeal_status: string | null
          created_at: string
          reason: string | null
          strike_count: number
          username: string
        }
        Insert: {
          acknowledged_at?: string | null
          appeal_status?: string | null
          created_at?: string
          reason?: string | null
          strike_count?: number
          username: string
        }
        Update: {
          acknowledged_at?: string | null
          appeal_status?: string | null
          created_at?: string
          reason?: string | null
          strike_count?: number
          username?: string
        }
        Relationships: []
      }
      whisper_liar_strikes: {
        Row: {
          claim: string | null
          created_at: string
          id: string
          reported_by_username: string | null
          target_username: string
          verdict: string
        }
        Insert: {
          claim?: string | null
          created_at?: string
          id?: string
          reported_by_username?: string | null
          target_username: string
          verdict: string
        }
        Update: {
          claim?: string | null
          created_at?: string
          id?: string
          reported_by_username?: string | null
          target_username?: string
          verdict?: string
        }
        Relationships: []
      }
      whisper_live_alerts: {
        Row: {
          created_at: string
          follower_id: string
          host_id: string
          host_username: string
          id: string
          room_id: string
          room_name: string
        }
        Insert: {
          created_at?: string
          follower_id: string
          host_id: string
          host_username?: string
          id?: string
          room_id: string
          room_name?: string
        }
        Update: {
          created_at?: string
          follower_id?: string
          host_id?: string
          host_username?: string
          id?: string
          room_id?: string
          room_name?: string
        }
        Relationships: []
      }
      whisper_live_bans: {
        Row: {
          banned_user_id: string
          banned_username: string
          created_at: string
          host_id: string
        }
        Insert: {
          banned_user_id: string
          banned_username?: string
          created_at?: string
          host_id: string
        }
        Update: {
          banned_user_id?: string
          banned_username?: string
          created_at?: string
          host_id?: string
        }
        Relationships: []
      }
      whisper_live_chat_messages: {
        Row: {
          body: string
          created_at: string
          id: string
          is_host: boolean
          is_pinned: boolean
          room_id: string
          user_id: string
          username: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          is_host?: boolean
          is_pinned?: boolean
          room_id: string
          user_id: string
          username: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          is_host?: boolean
          is_pinned?: boolean
          room_id?: string
          user_id?: string
          username?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_live_chat_messages_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "whisper_live_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_live_chat_poll_votes: {
        Row: {
          id: string
          option_index: number
          poll_id: string
          user_id: string
          voted_at: string
        }
        Insert: {
          id?: string
          option_index: number
          poll_id: string
          user_id: string
          voted_at?: string
        }
        Update: {
          id?: string
          option_index?: number
          poll_id?: string
          user_id?: string
          voted_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_live_chat_poll_votes_poll_id_fkey"
            columns: ["poll_id"]
            isOneToOne: false
            referencedRelation: "whisper_live_chat_polls"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_live_chat_polls: {
        Row: {
          closed_at: string | null
          created_at: string
          creator_id: string
          creator_username: string
          id: string
          options: Json
          question: string
          room_id: string
        }
        Insert: {
          closed_at?: string | null
          created_at?: string
          creator_id: string
          creator_username: string
          id?: string
          options: Json
          question: string
          room_id: string
        }
        Update: {
          closed_at?: string | null
          created_at?: string
          creator_id?: string
          creator_username?: string
          id?: string
          options?: Json
          question?: string
          room_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_live_chat_polls_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "whisper_live_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_live_gifts: {
        Row: {
          amount_cents: number
          created_at: string
          gift_emoji: string
          gift_id: string
          gift_label: string
          host_id: string
          id: string
          net_cents: number
          qty: number
          room_id: string
          sender_id: string
          sender_username: string | null
        }
        Insert: {
          amount_cents: number
          created_at?: string
          gift_emoji: string
          gift_id: string
          gift_label: string
          host_id: string
          id?: string
          net_cents: number
          qty?: number
          room_id: string
          sender_id: string
          sender_username?: string | null
        }
        Update: {
          amount_cents?: number
          created_at?: string
          gift_emoji?: string
          gift_id?: string
          gift_label?: string
          host_id?: string
          id?: string
          net_cents?: number
          qty?: number
          room_id?: string
          sender_id?: string
          sender_username?: string | null
        }
        Relationships: []
      }
      whisper_live_invites: {
        Row: {
          created_at: string
          id: string
          invitee_id: string
          inviter_id: string
          room_id: string
          status: string
        }
        Insert: {
          created_at?: string
          id?: string
          invitee_id: string
          inviter_id: string
          room_id: string
          status?: string
        }
        Update: {
          created_at?: string
          id?: string
          invitee_id?: string
          inviter_id?: string
          room_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_live_invites_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "whisper_live_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_live_moderators: {
        Row: {
          created_at: string
          host_id: string
          mod_user_id: string
          mod_username: string
        }
        Insert: {
          created_at?: string
          host_id: string
          mod_user_id: string
          mod_username?: string
        }
        Update: {
          created_at?: string
          host_id?: string
          mod_user_id?: string
          mod_username?: string
        }
        Relationships: []
      }
      whisper_live_room_listeners: {
        Row: {
          id: string
          joined_at: string
          room_id: string
          user_id: string
        }
        Insert: {
          id?: string
          joined_at?: string
          room_id: string
          user_id: string
        }
        Update: {
          id?: string
          joined_at?: string
          room_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_live_room_listeners_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "whisper_live_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_live_room_speakers: {
        Row: {
          can_video: boolean
          id: string
          is_cohost: boolean
          is_host: boolean
          joined_at: string
          left_at: string | null
          room_id: string
          user_id: string
        }
        Insert: {
          can_video?: boolean
          id?: string
          is_cohost?: boolean
          is_host?: boolean
          joined_at?: string
          left_at?: string | null
          room_id: string
          user_id: string
        }
        Update: {
          can_video?: boolean
          id?: string
          is_cohost?: boolean
          is_host?: boolean
          joined_at?: string
          left_at?: string | null
          room_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_live_room_speakers_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "whisper_live_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_live_rooms: {
        Row: {
          banned_words: string[]
          created_at: string
          description: string | null
          host_id: string
          id: string
          is_live: boolean
          is_video_enabled: boolean
          listener_count: number
          name: string
          peak_listeners: number
          scheduled_at: string | null
          topic: string | null
          updated_at: string
        }
        Insert: {
          banned_words?: string[]
          created_at?: string
          description?: string | null
          host_id: string
          id?: string
          is_live?: boolean
          is_video_enabled?: boolean
          listener_count?: number
          name: string
          peak_listeners?: number
          scheduled_at?: string | null
          topic?: string | null
          updated_at?: string
        }
        Update: {
          banned_words?: string[]
          created_at?: string
          description?: string | null
          host_id?: string
          id?: string
          is_live?: boolean
          is_video_enabled?: boolean
          listener_count?: number
          name?: string
          peak_listeners?: number
          scheduled_at?: string | null
          topic?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      whisper_live_speaker_requests: {
        Row: {
          answers: Json
          desired_role: string
          id: string
          requested_at: string
          reviewed_at: string | null
          reviewed_by: string | null
          room_id: string
          status: string
          user_id: string
        }
        Insert: {
          answers?: Json
          desired_role: string
          id?: string
          requested_at?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          room_id: string
          status?: string
          user_id: string
        }
        Update: {
          answers?: Json
          desired_role?: string
          id?: string
          requested_at?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          room_id?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_live_speaker_requests_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "whisper_live_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_live_timeouts: {
        Row: {
          created_at: string
          room_id: string
          until: string
          user_id: string
          username: string
        }
        Insert: {
          created_at?: string
          room_id: string
          until: string
          user_id: string
          username?: string
        }
        Update: {
          created_at?: string
          room_id?: string
          until?: string
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_meeting_backdrops: {
        Row: {
          created_at: string
          id: string
          prompt: string | null
          url: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          prompt?: string | null
          url: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          prompt?: string | null
          url?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_meeting_decks: {
        Row: {
          deck: Json
          meeting_id: string
          prospect_name: string | null
          recruiter_id: string
          updated_at: string
        }
        Insert: {
          deck: Json
          meeting_id: string
          prospect_name?: string | null
          recruiter_id: string
          updated_at?: string
        }
        Update: {
          deck?: Json
          meeting_id?: string
          prospect_name?: string | null
          recruiter_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_meeting_decks_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: false
            referencedRelation: "whisper_meetings"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_meeting_participants: {
        Row: {
          joined_at: string
          meeting_id: string
          user_id: string
          username: string
        }
        Insert: {
          joined_at?: string
          meeting_id: string
          user_id: string
          username?: string
        }
        Update: {
          joined_at?: string
          meeting_id?: string
          user_id?: string
          username?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_meeting_participants_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: false
            referencedRelation: "whisper_meetings"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_meeting_recaps: {
        Row: {
          meeting_id: string
          operation_id: string
          payload: Json
          rendered_summary: string
          updated_at: string
        }
        Insert: {
          meeting_id: string
          operation_id: string
          payload: Json
          rendered_summary: string
          updated_at?: string
        }
        Update: {
          meeting_id?: string
          operation_id?: string
          payload?: Json
          rendered_summary?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_meeting_recaps_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: true
            referencedRelation: "whisper_meetings"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_meeting_requests: {
        Row: {
          created_at: string
          decided_at: string | null
          featured_id: string | null
          id: string
          meeting_link: string | null
          message: string | null
          recruiter_id: string | null
          recruiter_note: string | null
          recruiter_username: string | null
          requested_time: string
          requester_email: string
          requester_name: string
          requester_timezone: string | null
          requester_user_id: string | null
          status: Database["public"]["Enums"]["whisper_meeting_status"]
        }
        Insert: {
          created_at?: string
          decided_at?: string | null
          featured_id?: string | null
          id?: string
          meeting_link?: string | null
          message?: string | null
          recruiter_id?: string | null
          recruiter_note?: string | null
          recruiter_username?: string | null
          requested_time: string
          requester_email: string
          requester_name?: string
          requester_timezone?: string | null
          requester_user_id?: string | null
          status?: Database["public"]["Enums"]["whisper_meeting_status"]
        }
        Update: {
          created_at?: string
          decided_at?: string | null
          featured_id?: string | null
          id?: string
          meeting_link?: string | null
          message?: string | null
          recruiter_id?: string | null
          recruiter_note?: string | null
          recruiter_username?: string | null
          requested_time?: string
          requester_email?: string
          requester_name?: string
          requester_timezone?: string | null
          requester_user_id?: string | null
          status?: Database["public"]["Enums"]["whisper_meeting_status"]
        }
        Relationships: []
      }
      whisper_meeting_transcripts: {
        Row: {
          capture_timing: Json | null
          id: string
          meeting_id: string
          spoken_at: string
          text: string
          user_id: string
          username: string
        }
        Insert: {
          capture_timing?: Json | null
          id?: string
          meeting_id: string
          spoken_at?: string
          text: string
          user_id: string
          username?: string
        }
        Update: {
          capture_timing?: Json | null
          id?: string
          meeting_id?: string
          spoken_at?: string
          text?: string
          user_id?: string
          username?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_meeting_transcripts_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: false
            referencedRelation: "whisper_meetings"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_meetings: {
        Row: {
          capture_notice: Json | null
          created_at: string
          ended_at: string | null
          host_id: string
          host_username: string
          id: string
          invited_emails: string[] | null
          scheduled_at: string | null
          started_at: string | null
          status: string
          summary: string | null
          summary_generated_at: string | null
          title: string
        }
        Insert: {
          capture_notice?: Json | null
          created_at?: string
          ended_at?: string | null
          host_id: string
          host_username?: string
          id?: string
          invited_emails?: string[] | null
          scheduled_at?: string | null
          started_at?: string | null
          status?: string
          summary?: string | null
          summary_generated_at?: string | null
          title?: string
        }
        Update: {
          capture_notice?: Json | null
          created_at?: string
          ended_at?: string | null
          host_id?: string
          host_username?: string
          id?: string
          invited_emails?: string[] | null
          scheduled_at?: string | null
          started_at?: string | null
          status?: string
          summary?: string | null
          summary_generated_at?: string | null
          title?: string
        }
        Relationships: []
      }
      whisper_mentions: {
        Row: {
          author_id: string
          created_at: string
          id: string
          mentioned_user_id: string | null
          mentioned_username: string
          source_id: string
          source_type: string
        }
        Insert: {
          author_id: string
          created_at?: string
          id?: string
          mentioned_user_id?: string | null
          mentioned_username: string
          source_id: string
          source_type: string
        }
        Update: {
          author_id?: string
          created_at?: string
          id?: string
          mentioned_user_id?: string | null
          mentioned_username?: string
          source_id?: string
          source_type?: string
        }
        Relationships: []
      }
      whisper_message_reaction_events: {
        Row: {
          actor_id: string
          created_at: string
          emoji: string
          group_id: string | null
          id: string
          message_id: string
          operation_id: string
          recipient_id: string
          target_id: string
        }
        Insert: {
          actor_id: string
          created_at?: string
          emoji: string
          group_id?: string | null
          id?: string
          message_id: string
          operation_id: string
          recipient_id: string
          target_id: string
        }
        Update: {
          actor_id?: string
          created_at?: string
          emoji?: string
          group_id?: string | null
          id?: string
          message_id?: string
          operation_id?: string
          recipient_id?: string
          target_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_message_reaction_events_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "whisper_group_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_message_reactions: {
        Row: {
          actor_id: string
          emoji: string | null
          operation_id: string
          target_id: string
          updated_at: string
        }
        Insert: {
          actor_id: string
          emoji?: string | null
          operation_id: string
          target_id: string
          updated_at?: string
        }
        Update: {
          actor_id?: string
          emoji?: string | null
          operation_id?: string
          target_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      whisper_messages: {
        Row: {
          body: string | null
          created_at: string
          embed: Json | null
          from_user_id: string
          from_username: string | null
          id: string
          logical_group_message_id: string | null
          media_url: string | null
          read_at: string | null
          thread_id: string
          to_user_id: string | null
          to_username: string | null
        }
        Insert: {
          body?: string | null
          created_at?: string
          embed?: Json | null
          from_user_id: string
          from_username?: string | null
          id?: string
          logical_group_message_id?: string | null
          media_url?: string | null
          read_at?: string | null
          thread_id: string
          to_user_id?: string | null
          to_username?: string | null
        }
        Update: {
          body?: string | null
          created_at?: string
          embed?: Json | null
          from_user_id?: string
          from_username?: string | null
          id?: string
          logical_group_message_id?: string | null
          media_url?: string | null
          read_at?: string | null
          thread_id?: string
          to_user_id?: string | null
          to_username?: string | null
        }
        Relationships: []
      }
      whisper_moderation_actions: {
        Row: {
          action: string
          created_at: string
          duration_minutes: number | null
          expires_at: string | null
          id: string
          issued_by_role: string
          issued_by_username: string
          reason: string | null
          scope: string
          target_user_id: string | null
          target_username: string
        }
        Insert: {
          action: string
          created_at?: string
          duration_minutes?: number | null
          expires_at?: string | null
          id?: string
          issued_by_role: string
          issued_by_username: string
          reason?: string | null
          scope?: string
          target_user_id?: string | null
          target_username: string
        }
        Update: {
          action?: string
          created_at?: string
          duration_minutes?: number | null
          expires_at?: string | null
          id?: string
          issued_by_role?: string
          issued_by_username?: string
          reason?: string | null
          scope?: string
          target_user_id?: string | null
          target_username?: string
        }
        Relationships: []
      }
      whisper_note_assets: {
        Row: {
          byte_count: number
          consent_at: string
          consent_version: string
          created_at: string
          height: number
          id: string
          mime_type: string
          owner_id: string
          sha256: string
          state: string
          version: number
          width: number
        }
        Insert: {
          byte_count: number
          consent_at: string
          consent_version: string
          created_at?: string
          height: number
          id: string
          mime_type: string
          owner_id: string
          sha256: string
          state?: string
          version?: number
          width: number
        }
        Update: {
          byte_count?: number
          consent_at?: string
          consent_version?: string
          created_at?: string
          height?: number
          id?: string
          mime_type?: string
          owner_id?: string
          sha256?: string
          state?: string
          version?: number
          width?: number
        }
        Relationships: []
      }
      whisper_notebook_prefs: {
        Row: {
          custom_title: string | null
          is_favorite: boolean
          meeting_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          custom_title?: string | null
          is_favorite?: boolean
          meeting_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          custom_title?: string | null
          is_favorite?: boolean
          meeting_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_notebook_prefs_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: false
            referencedRelation: "whisper_meetings"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_notes_filing: {
        Row: {
          documents: Json
          folders: Json
          migrations: Json
          owner_id: string
          updated_at: string
        }
        Insert: {
          documents?: Json
          folders?: Json
          migrations?: Json
          owner_id: string
          updated_at?: string
        }
        Update: {
          documents?: Json
          folders?: Json
          migrations?: Json
          owner_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      whisper_notes_meeting_documents: {
        Row: {
          created_at: string
          document_id: string
          meeting_id: string
          source_notebook: string
          source_owner: string
        }
        Insert: {
          created_at?: string
          document_id: string
          meeting_id: string
          source_notebook: string
          source_owner: string
        }
        Update: {
          created_at?: string
          document_id?: string
          meeting_id?: string
          source_notebook?: string
          source_owner?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_notes_meeting_documents_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: true
            referencedRelation: "whisper_shared_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whisper_notes_meeting_documents_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: true
            referencedRelation: "whisper_meetings"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_notes_meeting_sharing: {
        Row: {
          audience: string
          configured_by: string
          meeting_id: string
          operation_id: string
          published_at: string | null
          published_recipients: string[]
          recipients: string[]
          role: string
          updated_at: string
        }
        Insert: {
          audience: string
          configured_by: string
          meeting_id: string
          operation_id: string
          published_at?: string | null
          published_recipients?: string[]
          recipients?: string[]
          role: string
          updated_at?: string
        }
        Update: {
          audience?: string
          configured_by?: string
          meeting_id?: string
          operation_id?: string
          published_at?: string | null
          published_recipients?: string[]
          recipients?: string[]
          role?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_notes_meeting_sharing_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: true
            referencedRelation: "whisper_meetings"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_notes_message_receipts: {
        Row: {
          created_at: string
          document_id: string
          fingerprint: string
          id: string
          recipient_id: string
          sender_id: string
        }
        Insert: {
          created_at?: string
          document_id: string
          fingerprint: string
          id: string
          recipient_id: string
          sender_id: string
        }
        Update: {
          created_at?: string
          document_id?: string
          fingerprint?: string
          id?: string
          recipient_id?: string
          sender_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_notes_message_receipts_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "whisper_shared_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_notification_prefs: {
        Row: {
          comments: boolean
          dms: boolean
          follows: boolean
          likes: boolean
          master_enabled: boolean
          mentions: boolean
          missed_calls: boolean
          quiet_mode: boolean
          story_responses: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          comments?: boolean
          dms?: boolean
          follows?: boolean
          likes?: boolean
          master_enabled?: boolean
          mentions?: boolean
          missed_calls?: boolean
          quiet_mode?: boolean
          story_responses?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          comments?: boolean
          dms?: boolean
          follows?: boolean
          likes?: boolean
          master_enabled?: boolean
          mentions?: boolean
          missed_calls?: boolean
          quiet_mode?: boolean
          story_responses?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_one_members: {
        Row: {
          created_at: string
          email: string | null
          id: string
          plan: string
          status: string
          stripe_customer_id: string | null
          stripe_subscription_id: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          email?: string | null
          id?: string
          plan?: string
          status?: string
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          email?: string | null
          id?: string
          plan?: string
          status?: string
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      whisper_pinned_posts: {
        Row: {
          pinned_at: string
          position: number
          post_id: string
          user_id: string
        }
        Insert: {
          pinned_at?: string
          position?: number
          post_id: string
          user_id: string
        }
        Update: {
          pinned_at?: string
          position?: number
          post_id?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_post_comments: {
        Row: {
          body: string
          created_at: string
          id: string
          likes_count: number
          parent_comment_id: string | null
          parent_id: string | null
          post_id: string
          updated_at: string
          user_id: string
          username: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          likes_count?: number
          parent_comment_id?: string | null
          parent_id?: string | null
          post_id: string
          updated_at?: string
          user_id: string
          username?: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          likes_count?: number
          parent_comment_id?: string | null
          parent_id?: string | null
          post_id?: string
          updated_at?: string
          user_id?: string
          username?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_post_comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "whisper_post_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whisper_post_comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "whisper_post_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whisper_post_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "whisper_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_post_likes: {
        Row: {
          created_at: string
          post_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          post_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_post_likes_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "whisper_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_post_views: {
        Row: {
          id: number
          post_id: string
          viewed_at: string
          viewer_user_id: string
        }
        Insert: {
          id?: number
          post_id: string
          viewed_at?: string
          viewer_user_id: string
        }
        Update: {
          id?: number
          post_id?: string
          viewed_at?: string
          viewer_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_post_views_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "whisper_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_posts: {
        Row: {
          accent_hex: string | null
          caption: string
          comments_count: number
          community_id: string | null
          community_name: string | null
          created_at: string
          filter_id: string | null
          id: string
          is_ghost: boolean
          is_reel: boolean
          kind: string
          likes_count: number
          location: string | null
          media_count: number
          media_kind: string
          media_urls: string[]
          symbol: string | null
          user_id: string
          workout_id: string | null
        }
        Insert: {
          accent_hex?: string | null
          caption?: string
          comments_count?: number
          community_id?: string | null
          community_name?: string | null
          created_at?: string
          filter_id?: string | null
          id?: string
          is_ghost?: boolean
          is_reel?: boolean
          kind?: string
          likes_count?: number
          location?: string | null
          media_count?: number
          media_kind?: string
          media_urls?: string[]
          symbol?: string | null
          user_id: string
          workout_id?: string | null
        }
        Update: {
          accent_hex?: string | null
          caption?: string
          comments_count?: number
          community_id?: string | null
          community_name?: string | null
          created_at?: string
          filter_id?: string | null
          id?: string
          is_ghost?: boolean
          is_reel?: boolean
          kind?: string
          likes_count?: number
          location?: string | null
          media_count?: number
          media_kind?: string
          media_urls?: string[]
          symbol?: string | null
          user_id?: string
          workout_id?: string | null
        }
        Relationships: []
      }
      whisper_presence: {
        Row: {
          last_seen_at: string
          user_id: string
        }
        Insert: {
          last_seen_at?: string
          user_id: string
        }
        Update: {
          last_seen_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_private_notebooks: {
        Row: {
          deleted: boolean
          document: Json | null
          id: string
          operation_id: string
          owner_id: string
          revision: number
          updated_at: string
        }
        Insert: {
          deleted?: boolean
          document?: Json | null
          id: string
          operation_id: string
          owner_id: string
          revision: number
          updated_at?: string
        }
        Update: {
          deleted?: boolean
          document?: Json | null
          id?: string
          operation_id?: string
          owner_id?: string
          revision?: number
          updated_at?: string
        }
        Relationships: []
      }
      whisper_profiles: {
        Row: {
          accent_color: string | null
          account_type: string
          athlete_level: string | null
          athlete_sport: string | null
          banner_offset_y: number
          banner_url: string | null
          bio: string
          coach_tier: string | null
          coach_welcomed_at: string | null
          contact_email: string | null
          contact_phone: string | null
          created_at: string
          current_streak: number
          display_name: string | null
          ghost_enabled: boolean
          interests: string[]
          is_admin: boolean
          is_athlete: boolean
          is_blogger: boolean
          is_brand: boolean
          is_coach: boolean
          is_director: boolean
          is_liar: boolean
          is_moderator: boolean
          is_one: boolean | null
          is_owner: boolean
          is_plus: boolean
          is_private: boolean
          is_recruiter: boolean
          is_verified: boolean
          last_workout_at: string | null
          liar_reason: string | null
          link_url: string | null
          longest_streak: number
          onboarded_at: string
          one_plan: string | null
          plus_since: string | null
          professional_category: string | null
          profile_image_url: string | null
          total_volume_kg: number
          total_workouts: number
          updated_at: string
          user_id: string
          username: string
          verified_athlete: boolean
          verified_welcomed_at: string | null
        }
        Insert: {
          accent_color?: string | null
          account_type?: string
          athlete_level?: string | null
          athlete_sport?: string | null
          banner_offset_y?: number
          banner_url?: string | null
          bio?: string
          coach_tier?: string | null
          coach_welcomed_at?: string | null
          contact_email?: string | null
          contact_phone?: string | null
          created_at?: string
          current_streak?: number
          display_name?: string | null
          ghost_enabled?: boolean
          interests?: string[]
          is_admin?: boolean
          is_athlete?: boolean
          is_blogger?: boolean
          is_brand?: boolean
          is_coach?: boolean
          is_director?: boolean
          is_liar?: boolean
          is_moderator?: boolean
          is_one?: boolean | null
          is_owner?: boolean
          is_plus?: boolean
          is_private?: boolean
          is_recruiter?: boolean
          is_verified?: boolean
          last_workout_at?: string | null
          liar_reason?: string | null
          link_url?: string | null
          longest_streak?: number
          onboarded_at?: string
          one_plan?: string | null
          plus_since?: string | null
          professional_category?: string | null
          profile_image_url?: string | null
          total_volume_kg?: number
          total_workouts?: number
          updated_at?: string
          user_id: string
          username: string
          verified_athlete?: boolean
          verified_welcomed_at?: string | null
        }
        Update: {
          accent_color?: string | null
          account_type?: string
          athlete_level?: string | null
          athlete_sport?: string | null
          banner_offset_y?: number
          banner_url?: string | null
          bio?: string
          coach_tier?: string | null
          coach_welcomed_at?: string | null
          contact_email?: string | null
          contact_phone?: string | null
          created_at?: string
          current_streak?: number
          display_name?: string | null
          ghost_enabled?: boolean
          interests?: string[]
          is_admin?: boolean
          is_athlete?: boolean
          is_blogger?: boolean
          is_brand?: boolean
          is_coach?: boolean
          is_director?: boolean
          is_liar?: boolean
          is_moderator?: boolean
          is_one?: boolean | null
          is_owner?: boolean
          is_plus?: boolean
          is_private?: boolean
          is_recruiter?: boolean
          is_verified?: boolean
          last_workout_at?: string | null
          liar_reason?: string | null
          link_url?: string | null
          longest_streak?: number
          onboarded_at?: string
          one_plan?: string | null
          plus_since?: string | null
          professional_category?: string | null
          profile_image_url?: string | null
          total_volume_kg?: number
          total_workouts?: number
          updated_at?: string
          user_id?: string
          username?: string
          verified_athlete?: boolean
          verified_welcomed_at?: string | null
        }
        Relationships: []
      }
      whisper_proposal_receipts: {
        Row: {
          client_user_id: string
          message_id: string | null
          proposal_id: string
          responded_at: string
          status: string
        }
        Insert: {
          client_user_id: string
          message_id?: string | null
          proposal_id: string
          responded_at?: string
          status: string
        }
        Update: {
          client_user_id?: string
          message_id?: string | null
          proposal_id?: string
          responded_at?: string
          status?: string
        }
        Relationships: []
      }
      whisper_prospect_activities: {
        Row: {
          body: string
          created_at: string
          id: string
          kind: string
          prospect_id: string
          recruiter_id: string
        }
        Insert: {
          body?: string
          created_at?: string
          id?: string
          kind?: string
          prospect_id: string
          recruiter_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          kind?: string
          prospect_id?: string
          recruiter_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_prospect_activities_prospect_id_fkey"
            columns: ["prospect_id"]
            isOneToOne: false
            referencedRelation: "whisper_recruiter_prospects"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_push_group_mutes: {
        Row: {
          group_id: string
          muted: boolean
          user_id: string
        }
        Insert: {
          group_id: string
          muted?: boolean
          user_id: string
        }
        Update: {
          group_id?: string
          muted?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_push_group_mutes_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "whisper_group_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_push_receipts: {
        Row: {
          created_at: string
          event_key: string
        }
        Insert: {
          created_at?: string
          event_key: string
        }
        Update: {
          created_at?: string
          event_key?: string
        }
        Relationships: []
      }
      whisper_receipts: {
        Row: {
          amount_cents: number
          coach_user_id: string | null
          created_at: string
          currency: string
          description: string
          email: string | null
          id: string
          kind: string
          receipt_no: string
          refund_note: string | null
          refunded_at: string | null
          status: string
          stripe_invoice_id: string | null
          stripe_payment_intent: string | null
          stripe_session_id: string | null
          stripe_subscription_id: string | null
          user_id: string | null
        }
        Insert: {
          amount_cents?: number
          coach_user_id?: string | null
          created_at?: string
          currency?: string
          description?: string
          email?: string | null
          id?: string
          kind?: string
          receipt_no: string
          refund_note?: string | null
          refunded_at?: string | null
          status?: string
          stripe_invoice_id?: string | null
          stripe_payment_intent?: string | null
          stripe_session_id?: string | null
          stripe_subscription_id?: string | null
          user_id?: string | null
        }
        Update: {
          amount_cents?: number
          coach_user_id?: string | null
          created_at?: string
          currency?: string
          description?: string
          email?: string | null
          id?: string
          kind?: string
          receipt_no?: string
          refund_note?: string | null
          refunded_at?: string | null
          status?: string
          stripe_invoice_id?: string | null
          stripe_payment_intent?: string | null
          stripe_session_id?: string | null
          stripe_subscription_id?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      whisper_recording_archives: {
        Row: {
          audio_bytes: number
          created_at: string
          id: string
          media_bytes: number
          owner_id: string
          recording_id: string
          snapshot: Json
          source_revision: number
          state: string
        }
        Insert: {
          audio_bytes: number
          created_at?: string
          id?: string
          media_bytes: number
          owner_id: string
          recording_id: string
          snapshot: Json
          source_revision: number
          state?: string
        }
        Update: {
          audio_bytes?: number
          created_at?: string
          id?: string
          media_bytes?: number
          owner_id?: string
          recording_id?: string
          snapshot?: Json
          source_revision?: number
          state?: string
        }
        Relationships: []
      }
      whisper_recruiter_applications: {
        Row: {
          bio: string | null
          created_at: string
          email: string | null
          experience: string | null
          full_name: string
          id: string
          region: string | null
          social: string | null
          status: Database["public"]["Enums"]["whisper_application_status"]
          user_id: string | null
          username: string
        }
        Insert: {
          bio?: string | null
          created_at?: string
          email?: string | null
          experience?: string | null
          full_name?: string
          id?: string
          region?: string | null
          social?: string | null
          status?: Database["public"]["Enums"]["whisper_application_status"]
          user_id?: string | null
          username: string
        }
        Update: {
          bio?: string | null
          created_at?: string
          email?: string | null
          experience?: string | null
          full_name?: string
          id?: string
          region?: string | null
          social?: string | null
          status?: Database["public"]["Enums"]["whisper_application_status"]
          user_id?: string | null
          username?: string
        }
        Relationships: []
      }
      whisper_recruiter_groups: {
        Row: {
          created_at: string
          id: string
          name: string
          photo_url: string | null
          recruiter_id: string
          territory_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          photo_url?: string | null
          recruiter_id: string
          territory_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          photo_url?: string | null
          recruiter_id?: string
          territory_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_recruiter_groups_territory_id_fkey"
            columns: ["territory_id"]
            isOneToOne: false
            referencedRelation: "whisper_recruiter_territories"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_recruiter_promotions: {
        Row: {
          created_at: string
          id: string
          notes: string | null
          promoted_id: string
          promoted_username: string
          recruiter_id: string
          recruiter_username: string | null
          role: string
        }
        Insert: {
          created_at?: string
          id?: string
          notes?: string | null
          promoted_id: string
          promoted_username: string
          recruiter_id: string
          recruiter_username?: string | null
          role: string
        }
        Update: {
          created_at?: string
          id?: string
          notes?: string | null
          promoted_id?: string
          promoted_username?: string
          recruiter_id?: string
          recruiter_username?: string | null
          role?: string
        }
        Relationships: []
      }
      whisper_recruiter_prospects: {
        Row: {
          contact_log: Json
          created_at: string
          id: string
          instagram: string | null
          last_touch_at: string | null
          location: string | null
          next_action: string | null
          next_action_due: string | null
          niche: string | null
          notes: string | null
          prospect_display_name: string | null
          prospect_image_url: string | null
          prospect_user_id: string | null
          prospect_username: string | null
          rating: number | null
          recruiter_id: string
          scorecard: Json
          source: string | null
          status: Database["public"]["Enums"]["whisper_prospect_status"]
          suggested_role: string | null
          tags: string[]
          tiktok: string | null
          updated_at: string
        }
        Insert: {
          contact_log?: Json
          created_at?: string
          id?: string
          instagram?: string | null
          last_touch_at?: string | null
          location?: string | null
          next_action?: string | null
          next_action_due?: string | null
          niche?: string | null
          notes?: string | null
          prospect_display_name?: string | null
          prospect_image_url?: string | null
          prospect_user_id?: string | null
          prospect_username?: string | null
          rating?: number | null
          recruiter_id: string
          scorecard?: Json
          source?: string | null
          status?: Database["public"]["Enums"]["whisper_prospect_status"]
          suggested_role?: string | null
          tags?: string[]
          tiktok?: string | null
          updated_at?: string
        }
        Update: {
          contact_log?: Json
          created_at?: string
          id?: string
          instagram?: string | null
          last_touch_at?: string | null
          location?: string | null
          next_action?: string | null
          next_action_due?: string | null
          niche?: string | null
          notes?: string | null
          prospect_display_name?: string | null
          prospect_image_url?: string | null
          prospect_user_id?: string | null
          prospect_username?: string | null
          rating?: number | null
          recruiter_id?: string
          scorecard?: Json
          source?: string | null
          status?: Database["public"]["Enums"]["whisper_prospect_status"]
          suggested_role?: string | null
          tags?: string[]
          tiktok?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      whisper_recruiter_reviews: {
        Row: {
          created_at: string
          id: string
          rating: number
          recruiter_id: string
          review: string | null
          reviewer_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          rating: number
          recruiter_id: string
          review?: string | null
          reviewer_id: string
        }
        Update: {
          created_at?: string
          id?: string
          rating?: number
          recruiter_id?: string
          review?: string | null
          reviewer_id?: string
        }
        Relationships: []
      }
      whisper_recruiter_targets: {
        Row: {
          created_at: string
          id: string
          notes: string | null
          period: string
          recruiter_id: string
          target_athlete: number
          target_coach: number
          target_creator: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          notes?: string | null
          period: string
          recruiter_id: string
          target_athlete?: number
          target_coach?: number
          target_creator?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          notes?: string | null
          period?: string
          recruiter_id?: string
          target_athlete?: number
          target_coach?: number
          target_creator?: number
          updated_at?: string
        }
        Relationships: []
      }
      whisper_recruiter_territories: {
        Row: {
          cities: string | null
          color: string | null
          created_at: string
          id: string
          name: string
          notes: string | null
          recruiter_id: string
          region: string
        }
        Insert: {
          cities?: string | null
          color?: string | null
          created_at?: string
          id?: string
          name: string
          notes?: string | null
          recruiter_id: string
          region?: string
        }
        Update: {
          cities?: string | null
          color?: string | null
          created_at?: string
          id?: string
          name?: string
          notes?: string | null
          recruiter_id?: string
          region?: string
        }
        Relationships: []
      }
      whisper_referral_codes: {
        Row: {
          code: string
          created_at: string
          id: string
          recruiter_id: string
          uses: number
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          recruiter_id: string
          uses?: number
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          recruiter_id?: string
          uses?: number
        }
        Relationships: []
      }
      whisper_referral_signups: {
        Row: {
          code_id: string
          created_at: string
          id: string
          new_user_id: string
          recruiter_id: string
        }
        Insert: {
          code_id: string
          created_at?: string
          id?: string
          new_user_id: string
          recruiter_id: string
        }
        Update: {
          code_id?: string
          created_at?: string
          id?: string
          new_user_id?: string
          recruiter_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_referral_signups_code_id_fkey"
            columns: ["code_id"]
            isOneToOne: false
            referencedRelation: "whisper_referral_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_refund_requests: {
        Row: {
          admin_note: string | null
          amount_cents: number | null
          coach_user_id: string | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          eligible_auto: boolean
          email: string | null
          id: string
          kind: string
          reason: string | null
          reference: string | null
          status: string
          stripe_refund_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          admin_note?: string | null
          amount_cents?: number | null
          coach_user_id?: string | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          eligible_auto?: boolean
          email?: string | null
          id?: string
          kind: string
          reason?: string | null
          reference?: string | null
          status?: string
          stripe_refund_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          admin_note?: string | null
          amount_cents?: number | null
          coach_user_id?: string | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          eligible_auto?: boolean
          email?: string | null
          id?: string
          kind?: string
          reason?: string | null
          reference?: string | null
          status?: string
          stripe_refund_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_reports: {
        Row: {
          context: Json
          created_at: string
          details: string | null
          id: string
          post_snapshot: Json | null
          reason: string
          reporter_id: string
          reporter_username: string | null
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          target_id: string | null
          target_kind: string
          target_user_id: string | null
          target_username: string | null
        }
        Insert: {
          context?: Json
          created_at?: string
          details?: string | null
          id?: string
          post_snapshot?: Json | null
          reason: string
          reporter_id: string
          reporter_username?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          target_id?: string | null
          target_kind: string
          target_user_id?: string | null
          target_username?: string | null
        }
        Update: {
          context?: Json
          created_at?: string
          details?: string | null
          id?: string
          post_snapshot?: Json | null
          reason?: string
          reporter_id?: string
          reporter_username?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          target_id?: string | null
          target_kind?: string
          target_user_id?: string | null
          target_username?: string | null
        }
        Relationships: []
      }
      whisper_reposts: {
        Row: {
          created_at: string
          post_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          post_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          post_id?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_safety_flags: {
        Row: {
          created_at: string
          last_strike_at: string | null
          reason: string | null
          strike_count: number
          user_id: string
          username: string | null
        }
        Insert: {
          created_at?: string
          last_strike_at?: string | null
          reason?: string | null
          strike_count?: number
          user_id: string
          username?: string | null
        }
        Update: {
          created_at?: string
          last_strike_at?: string | null
          reason?: string | null
          strike_count?: number
          user_id?: string
          username?: string | null
        }
        Relationships: []
      }
      whisper_safety_strikes: {
        Row: {
          category: string
          created_at: string
          excerpt: string | null
          id: string
          other_user_id: string | null
          reasoning: string | null
          reporter_user_id: string | null
          severity: string
          target_user_id: string
          target_username: string | null
        }
        Insert: {
          category: string
          created_at?: string
          excerpt?: string | null
          id?: string
          other_user_id?: string | null
          reasoning?: string | null
          reporter_user_id?: string | null
          severity: string
          target_user_id: string
          target_username?: string | null
        }
        Update: {
          category?: string
          created_at?: string
          excerpt?: string | null
          id?: string
          other_user_id?: string | null
          reasoning?: string | null
          reporter_user_id?: string | null
          severity?: string
          target_user_id?: string
          target_username?: string | null
        }
        Relationships: []
      }
      whisper_shared_documents: {
        Row: {
          bytes: number
          created_at: string
          deleted: boolean
          id: string
          owner_id: string
          seed: Json
          seq: number
          title: string
          updated_at: string
        }
        Insert: {
          bytes?: number
          created_at?: string
          deleted?: boolean
          id: string
          owner_id: string
          seed: Json
          seq?: number
          title: string
          updated_at?: string
        }
        Update: {
          bytes?: number
          created_at?: string
          deleted?: boolean
          id?: string
          owner_id?: string
          seed?: Json
          seq?: number
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      whisper_sign_artifacts: {
        Row: {
          kind: string
          pdf: string
          preview: Json | null
          request_id: string
          sha256: string
        }
        Insert: {
          kind: string
          pdf: string
          preview?: Json | null
          request_id: string
          sha256: string
        }
        Update: {
          kind?: string
          pdf?: string
          preview?: Json | null
          request_id?: string
          sha256?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_sign_artifacts_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "whisper_sign_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_sign_challenges: {
        Row: {
          attempts: number
          code_hash: string | null
          expires_at: string
          id: string
          request_id: string
        }
        Insert: {
          attempts?: number
          code_hash?: string | null
          expires_at: string
          id: string
          request_id: string
        }
        Update: {
          attempts?: number
          code_hash?: string | null
          expires_at?: string
          id?: string
          request_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_sign_challenges_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "whisper_sign_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_sign_events: {
        Row: {
          detail: Json
          id: number
          kind: string
          occurred_at: string
          request_id: string
        }
        Insert: {
          detail?: Json
          id?: never
          kind: string
          occurred_at?: string
          request_id: string
        }
        Update: {
          detail?: Json
          id?: never
          kind?: string
          occurred_at?: string
          request_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_sign_events_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "whisper_sign_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_sign_requests: {
        Row: {
          challenge_id: string | null
          code_at: string | null
          code_attempts: number
          code_count: number
          code_hash: string | null
          code_until: string | null
          code_window_at: string | null
          completed_at: string | null
          created_at: string
          document_id: string
          expires_at: string
          final_hash: string | null
          fingerprint: string
          id: string
          mail_at: string | null
          mail_count: number
          mail_id: string | null
          mail_status: string
          owner_id: string
          page_count: number
          receipt: Json | null
          recipient_email: string
          recipient_name: string
          sent_at: string | null
          session_hash: string | null
          session_until: string | null
          signed_at: string | null
          source_app: string
          source_hash: string
          source_seq: number
          status: string
          title: string
          verified_at: string | null
        }
        Insert: {
          challenge_id?: string | null
          code_at?: string | null
          code_attempts?: number
          code_count?: number
          code_hash?: string | null
          code_until?: string | null
          code_window_at?: string | null
          completed_at?: string | null
          created_at?: string
          document_id: string
          expires_at?: string
          final_hash?: string | null
          fingerprint: string
          id: string
          mail_at?: string | null
          mail_count?: number
          mail_id?: string | null
          mail_status?: string
          owner_id: string
          page_count: number
          receipt?: Json | null
          recipient_email: string
          recipient_name: string
          sent_at?: string | null
          session_hash?: string | null
          session_until?: string | null
          signed_at?: string | null
          source_app?: string
          source_hash: string
          source_seq: number
          status?: string
          title: string
          verified_at?: string | null
        }
        Update: {
          challenge_id?: string | null
          code_at?: string | null
          code_attempts?: number
          code_count?: number
          code_hash?: string | null
          code_until?: string | null
          code_window_at?: string | null
          completed_at?: string | null
          created_at?: string
          document_id?: string
          expires_at?: string
          final_hash?: string | null
          fingerprint?: string
          id?: string
          mail_at?: string | null
          mail_count?: number
          mail_id?: string | null
          mail_status?: string
          owner_id?: string
          page_count?: number
          receipt?: Json | null
          recipient_email?: string
          recipient_name?: string
          sent_at?: string | null
          session_hash?: string | null
          session_until?: string | null
          signed_at?: string | null
          source_app?: string
          source_hash?: string
          source_seq?: number
          status?: string
          title?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "whisper_sign_requests_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "whisper_shared_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_sign_throttles: {
        Row: {
          hits: number
          key: string
          started_at: string
        }
        Insert: {
          hits?: number
          key: string
          started_at?: string
        }
        Update: {
          hits?: number
          key?: string
          started_at?: string
        }
        Relationships: []
      }
      whisper_sponsorship_applications: {
        Row: {
          brand_company: string | null
          brand_user_id: string
          created_at: string
          creator_age: number | null
          creator_followers: number | null
          creator_user_id: string
          creator_username: string | null
          desired_amount_cents: number
          desired_basis: string
          id: string
          message: string | null
          status: string
          terms_amount_cents: number | null
          terms_basis: string | null
          terms_deliverables: string | null
          terms_exclusive: boolean
          terms_expires_at: string | null
          terms_notes: string | null
          updated_at: string
        }
        Insert: {
          brand_company?: string | null
          brand_user_id: string
          created_at?: string
          creator_age?: number | null
          creator_followers?: number | null
          creator_user_id: string
          creator_username?: string | null
          desired_amount_cents: number
          desired_basis: string
          id?: string
          message?: string | null
          status?: string
          terms_amount_cents?: number | null
          terms_basis?: string | null
          terms_deliverables?: string | null
          terms_exclusive?: boolean
          terms_expires_at?: string | null
          terms_notes?: string | null
          updated_at?: string
        }
        Update: {
          brand_company?: string | null
          brand_user_id?: string
          created_at?: string
          creator_age?: number | null
          creator_followers?: number | null
          creator_user_id?: string
          creator_username?: string | null
          desired_amount_cents?: number
          desired_basis?: string
          id?: string
          message?: string | null
          status?: string
          terms_amount_cents?: number | null
          terms_basis?: string | null
          terms_deliverables?: string | null
          terms_exclusive?: boolean
          terms_expires_at?: string | null
          terms_notes?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      whisper_sponsorship_deals: {
        Row: {
          amount_cents: number
          application_id: string | null
          basis: string
          brand_company: string | null
          brand_user_id: string
          created_at: string
          creator_user_id: string
          creator_username: string | null
          deliverables: string | null
          exclusive: boolean
          id: string
          notes: string | null
          status: string
          updated_at: string
        }
        Insert: {
          amount_cents: number
          application_id?: string | null
          basis: string
          brand_company?: string | null
          brand_user_id: string
          created_at?: string
          creator_user_id: string
          creator_username?: string | null
          deliverables?: string | null
          exclusive?: boolean
          id?: string
          notes?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          amount_cents?: number
          application_id?: string | null
          basis?: string
          brand_company?: string | null
          brand_user_id?: string
          created_at?: string
          creator_user_id?: string
          creator_username?: string | null
          deliverables?: string | null
          exclusive?: boolean
          id?: string
          notes?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      whisper_sponsorship_payments: {
        Row: {
          brand_user_id: string | null
          created_at: string
          creator_user_id: string | null
          deal_id: string
          dispute_reason: string | null
          fee_cents: number
          gross_cents: number
          hold_until: string | null
          id: string
          net_cents: number
          refunded_at: string | null
          released_at: string | null
          requires_post: boolean
          status: string
          stripe_payment_intent: string | null
          stripe_refund_id: string | null
          stripe_session_id: string | null
          stripe_transfer_id: string | null
        }
        Insert: {
          brand_user_id?: string | null
          created_at?: string
          creator_user_id?: string | null
          deal_id: string
          dispute_reason?: string | null
          fee_cents?: number
          gross_cents: number
          hold_until?: string | null
          id?: string
          net_cents: number
          refunded_at?: string | null
          released_at?: string | null
          requires_post?: boolean
          status?: string
          stripe_payment_intent?: string | null
          stripe_refund_id?: string | null
          stripe_session_id?: string | null
          stripe_transfer_id?: string | null
        }
        Update: {
          brand_user_id?: string | null
          created_at?: string
          creator_user_id?: string | null
          deal_id?: string
          dispute_reason?: string | null
          fee_cents?: number
          gross_cents?: number
          hold_until?: string | null
          id?: string
          net_cents?: number
          refunded_at?: string | null
          released_at?: string | null
          requires_post?: boolean
          status?: string
          stripe_payment_intent?: string | null
          stripe_refund_id?: string | null
          stripe_session_id?: string | null
          stripe_transfer_id?: string | null
        }
        Relationships: []
      }
      whisper_sponsorship_posts: {
        Row: {
          brand_user_id: string | null
          comments_count: number
          created_at: string
          creator_user_id: string | null
          deal_id: string
          id: string
          likes_count: number
          post_id: string
        }
        Insert: {
          brand_user_id?: string | null
          comments_count?: number
          created_at?: string
          creator_user_id?: string | null
          deal_id: string
          id?: string
          likes_count?: number
          post_id: string
        }
        Update: {
          brand_user_id?: string | null
          comments_count?: number
          created_at?: string
          creator_user_id?: string | null
          deal_id?: string
          id?: string
          likes_count?: number
          post_id?: string
        }
        Relationships: []
      }
      whisper_stories: {
        Row: {
          caption: string | null
          created_at: string
          expires_at: string
          id: string
          image_url: string | null
          is_ghost: boolean
          media_url: string | null
          metadata: Json | null
          music_artist: string | null
          music_artwork: string | null
          music_title: string | null
          music_url: string | null
          user_id: string
          username: string | null
          video_url: string | null
        }
        Insert: {
          caption?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          image_url?: string | null
          is_ghost?: boolean
          media_url?: string | null
          metadata?: Json | null
          music_artist?: string | null
          music_artwork?: string | null
          music_title?: string | null
          music_url?: string | null
          user_id: string
          username?: string | null
          video_url?: string | null
        }
        Update: {
          caption?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          image_url?: string | null
          is_ghost?: boolean
          media_url?: string | null
          metadata?: Json | null
          music_artist?: string | null
          music_artwork?: string | null
          music_title?: string | null
          music_url?: string | null
          user_id?: string
          username?: string | null
          video_url?: string | null
        }
        Relationships: []
      }
      whisper_story_highlight_items: {
        Row: {
          caption: string | null
          created_at: string
          highlight_id: string
          id: string
          image_url: string
          metadata: string | null
          music_artist: string | null
          music_artwork: string | null
          music_title: string | null
          music_url: string | null
          position: number
          user_id: string
        }
        Insert: {
          caption?: string | null
          created_at?: string
          highlight_id: string
          id?: string
          image_url: string
          metadata?: string | null
          music_artist?: string | null
          music_artwork?: string | null
          music_title?: string | null
          music_url?: string | null
          position?: number
          user_id: string
        }
        Update: {
          caption?: string | null
          created_at?: string
          highlight_id?: string
          id?: string
          image_url?: string
          metadata?: string | null
          music_artist?: string | null
          music_artwork?: string | null
          music_title?: string | null
          music_url?: string | null
          position?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_story_highlight_items_highlight_id_fkey"
            columns: ["highlight_id"]
            isOneToOne: false
            referencedRelation: "whisper_story_highlights"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_story_highlights: {
        Row: {
          cover_url: string | null
          created_at: string
          id: string
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          cover_url?: string | null
          created_at?: string
          id?: string
          title: string
          updated_at?: string
          user_id: string
        }
        Update: {
          cover_url?: string | null
          created_at?: string
          id?: string
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_story_responses: {
        Row: {
          created_at: string
          id: string
          kind: string
          prompt: string
          read_at: string | null
          responder_id: string
          responder_username: string
          response: string
          story_id: string
          story_owner_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind: string
          prompt: string
          read_at?: string | null
          responder_id: string
          responder_username: string
          response: string
          story_id: string
          story_owner_id: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          prompt?: string
          read_at?: string | null
          responder_id?: string
          responder_username?: string
          response?: string
          story_id?: string
          story_owner_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_story_responses_story_id_fkey"
            columns: ["story_id"]
            isOneToOne: false
            referencedRelation: "whisper_stories"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_story_views: {
        Row: {
          created_at: string
          story_id: string
          story_owner_id: string
          viewer_id: string
          viewer_username: string
        }
        Insert: {
          created_at?: string
          story_id: string
          story_owner_id: string
          viewer_id: string
          viewer_username: string
        }
        Update: {
          created_at?: string
          story_id?: string
          story_owner_id?: string
          viewer_id?: string
          viewer_username?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_story_views_story_id_fkey"
            columns: ["story_id"]
            isOneToOne: false
            referencedRelation: "whisper_stories"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_team_events_v1: {
        Row: {
          cancelled: boolean
          created_at: string
          id: string
          owner_id: string
          payload: Json
          revision: number
          team_id: string
        }
        Insert: {
          cancelled?: boolean
          created_at?: string
          id: string
          owner_id: string
          payload: Json
          revision?: number
          team_id: string
        }
        Update: {
          cancelled?: boolean
          created_at?: string
          id?: string
          owner_id?: string
          payload?: Json
          revision?: number
          team_id?: string
        }
        Relationships: []
      }
      whisper_teams_dm_receipts_v1: {
        Row: {
          created_at: string
          invitation_id: string
          message_id: string
          recipient_id: string
          sender_id: string
          team_id: string
        }
        Insert: {
          created_at?: string
          invitation_id: string
          message_id: string
          recipient_id: string
          sender_id: string
          team_id: string
        }
        Update: {
          created_at?: string
          invitation_id?: string
          message_id?: string
          recipient_id?: string
          sender_id?: string
          team_id?: string
        }
        Relationships: []
      }
      whisper_teams_jasper_state: {
        Row: {
          enabled: boolean
          facts: Json
          generation: string
          owner_id: string
          revision: number
          updated_at: string
        }
        Insert: {
          enabled?: boolean
          facts?: Json
          generation?: string
          owner_id: string
          revision?: number
          updated_at?: string
        }
        Update: {
          enabled?: boolean
          facts?: Json
          generation?: string
          owner_id?: string
          revision?: number
          updated_at?: string
        }
        Relationships: []
      }
      whisper_teams_jasper_turns: {
        Row: {
          answer: string
          context_key: string
          created_at: string
          id: string
          owner_id: string
          question: string
          scope: string
        }
        Insert: {
          answer: string
          context_key: string
          created_at?: string
          id: string
          owner_id: string
          question: string
          scope: string
        }
        Update: {
          answer?: string
          context_key?: string
          created_at?: string
          id?: string
          owner_id?: string
          question?: string
          scope?: string
        }
        Relationships: []
      }
      whisper_thought_replies: {
        Row: {
          body: string
          created_at: string
          id: string
          read_at: string | null
          replier_avatar_url: string | null
          replier_user_id: string
          replier_username: string
          thought_accent: string | null
          thought_color_hex: string | null
          thought_emoji: string | null
          thought_owner_username: string | null
          thought_style: string | null
          thought_text: string
          thought_user_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          read_at?: string | null
          replier_avatar_url?: string | null
          replier_user_id: string
          replier_username: string
          thought_accent?: string | null
          thought_color_hex?: string | null
          thought_emoji?: string | null
          thought_owner_username?: string | null
          thought_style?: string | null
          thought_text?: string
          thought_user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          read_at?: string | null
          replier_avatar_url?: string | null
          replier_user_id?: string
          replier_username?: string
          thought_accent?: string | null
          thought_color_hex?: string | null
          thought_emoji?: string | null
          thought_owner_username?: string | null
          thought_style?: string | null
          thought_text?: string
          thought_user_id?: string
        }
        Relationships: []
      }
      whisper_thoughts: {
        Row: {
          accent: string | null
          body: string
          color_hex: string | null
          emoji: string | null
          expires_at: string
          posted_at: string
          style: string | null
          user_id: string
        }
        Insert: {
          accent?: string | null
          body: string
          color_hex?: string | null
          emoji?: string | null
          expires_at?: string
          posted_at?: string
          style?: string | null
          user_id: string
        }
        Update: {
          accent?: string | null
          body?: string
          color_hex?: string | null
          emoji?: string | null
          expires_at?: string
          posted_at?: string
          style?: string | null
          user_id?: string
        }
        Relationships: []
      }
      whisper_thread_members: {
        Row: {
          joined_at: string
          thread_id: string
          user_id: string
        }
        Insert: {
          joined_at?: string
          thread_id: string
          user_id: string
        }
        Update: {
          joined_at?: string
          thread_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whisper_thread_members_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "whisper_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_threads: {
        Row: {
          created_at: string
          id: string
          last_message_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          last_message_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          last_message_at?: string
        }
        Relationships: []
      }
      whisper_verification_requests: {
        Row: {
          category: string
          created_at: string
          email: string | null
          followers: number
          full_name: string
          id: string
          id_url: string | null
          links: string | null
          reason: string
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["whisper_application_status"]
          user_id: string
          username: string
        }
        Insert: {
          category: string
          created_at?: string
          email?: string | null
          followers?: number
          full_name: string
          id?: string
          id_url?: string | null
          links?: string | null
          reason?: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["whisper_application_status"]
          user_id: string
          username: string
        }
        Update: {
          category?: string
          created_at?: string
          email?: string | null
          followers?: number
          full_name?: string
          id?: string
          id_url?: string | null
          links?: string | null
          reason?: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["whisper_application_status"]
          user_id?: string
          username?: string
        }
        Relationships: []
      }
      whisper_voip_tokens: {
        Row: {
          bundle_id: string | null
          created_at: string
          environment: string
          token: string
          updated_at: string
          user_id: string
        }
        Insert: {
          bundle_id?: string | null
          created_at?: string
          environment?: string
          token: string
          updated_at?: string
          user_id: string
        }
        Update: {
          bundle_id?: string | null
          created_at?: string
          environment?: string
          token?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_wpp_cashouts: {
        Row: {
          amount_cents: number
          created_at: string
          id: string
          rpm_cents: number
          user_id: string
          views_counted: number
        }
        Insert: {
          amount_cents: number
          created_at?: string
          id?: string
          rpm_cents?: number
          user_id: string
          views_counted?: number
        }
        Update: {
          amount_cents?: number
          created_at?: string
          id?: string
          rpm_cents?: number
          user_id?: string
          views_counted?: number
        }
        Relationships: []
      }
      whisper_wpp_overrides: {
        Row: {
          created_at: string
          note: string | null
          tier_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          note?: string | null
          tier_id?: string
          user_id: string
        }
        Update: {
          created_at?: string
          note?: string | null
          tier_id?: string
          user_id?: string
        }
        Relationships: []
      }
      whisper_wpp_views: {
        Row: {
          created_at: string
          creator_user_id: string
          day: string
          id: number
          post_id: string
          viewer_id: string
        }
        Insert: {
          created_at?: string
          creator_user_id: string
          day?: string
          id?: never
          post_id: string
          viewer_id: string
        }
        Update: {
          created_at?: string
          creator_user_id?: string
          day?: string
          id?: never
          post_id?: string
          viewer_id?: string
        }
        Relationships: []
      }
      workout_session_history: {
        Row: {
          avg_heart_rate: number
          avg_oxygen_saturation: number
          calories_burned: number
          completed_sets: number
          created_at: string
          custom_name: string | null
          day_name: string | null
          display_name: string | null
          duration_seconds: number
          exercise_count: number
          exercises: Json | null
          focus: string | null
          heart_rate_timeline: Json | null
          id: string
          peak_heart_rate: number
          performed_at: string
          program_id: string | null
          summary: string | null
          total_reps: number
          total_sets: number
          total_weight_lbs: number
          user_id: string
          user_rating: number
        }
        Insert: {
          avg_heart_rate?: number
          avg_oxygen_saturation?: number
          calories_burned?: number
          completed_sets?: number
          created_at?: string
          custom_name?: string | null
          day_name?: string | null
          display_name?: string | null
          duration_seconds?: number
          exercise_count?: number
          exercises?: Json | null
          focus?: string | null
          heart_rate_timeline?: Json | null
          id: string
          peak_heart_rate?: number
          performed_at: string
          program_id?: string | null
          summary?: string | null
          total_reps?: number
          total_sets?: number
          total_weight_lbs?: number
          user_id: string
          user_rating?: number
        }
        Update: {
          avg_heart_rate?: number
          avg_oxygen_saturation?: number
          calories_burned?: number
          completed_sets?: number
          created_at?: string
          custom_name?: string | null
          day_name?: string | null
          display_name?: string | null
          duration_seconds?: number
          exercise_count?: number
          exercises?: Json | null
          focus?: string | null
          heart_rate_timeline?: Json | null
          id?: string
          peak_heart_rate?: number
          performed_at?: string
          program_id?: string | null
          summary?: string | null
          total_reps?: number
          total_sets?: number
          total_weight_lbs?: number
          user_id?: string
          user_rating?: number
        }
        Relationships: []
      }
      workout_sessions: {
        Row: {
          duration_sec: number | null
          ended_at: string | null
          exercises: Json
          id: string
          notes: string | null
          perceived_effort: number | null
          plan_id: string | null
          plan_title: string | null
          started_at: string
          total_volume_lbs: number | null
          user_id: string
        }
        Insert: {
          duration_sec?: number | null
          ended_at?: string | null
          exercises?: Json
          id?: string
          notes?: string | null
          perceived_effort?: number | null
          plan_id?: string | null
          plan_title?: string | null
          started_at: string
          total_volume_lbs?: number | null
          user_id: string
        }
        Update: {
          duration_sec?: number | null
          ended_at?: string | null
          exercises?: Json
          id?: string
          notes?: string | null
          perceived_effort?: number | null
          plan_id?: string | null
          plan_title?: string | null
          started_at?: string
          total_volume_lbs?: number | null
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      jasper_goal_plans_v: {
        Row: {
          goal: Json | null
          updated_at: string | null
          user_id: string | null
        }
        Relationships: []
      }
      jasper_weight_log_v: {
        Row: {
          kg: number | null
          measured_at: string | null
          pounds: number | null
          updated_at: string | null
          user_id: string | null
        }
        Relationships: []
      }
      whisper_film_reaction_counts: {
        Row: {
          dislike_count: number | null
          film_id: string | null
          like_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "whisper_film_reactions_film_id_fkey"
            columns: ["film_id"]
            isOneToOne: false
            referencedRelation: "whisper_films"
            referencedColumns: ["id"]
          },
        ]
      }
      whisper_recruiter_rating_summary: {
        Row: {
          average_rating: number | null
          negative_count: number | null
          positive_count: number | null
          recruiter_id: string | null
          review_count: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      accept_friend_request: { Args: { req_id: string }; Returns: undefined }
      business_active_ads: {
        Args: { p_limit?: number; p_placement?: string }
        Returns: {
          body: string
          business_logo_url: string
          business_name: string
          business_website: string
          cta_label: string
          cta_url: string
          headline: string
          id: string
          image_url: string
          media_type: string
          video_url: string
        }[]
      }
      business_ad_daily_stats: {
        Args: never
        Returns: {
          ad_id: string
          clicks: number
          day: string
          impressions: number
        }[]
      }
      business_ad_spend_cents: { Args: { p_user: string }; Returns: number }
      business_ads_library: {
        Args: { p_limit?: number; p_query?: string }
        Returns: {
          body: string
          business_logo_url: string
          business_name: string
          cta_label: string
          cta_url: string
          headline: string
          id: string
          image_url: string
          media_type: string
          objective: string
          placements: string[]
          started_at: string
          video_url: string
        }[]
      }
      business_track_ad: {
        Args: { p_ad: string; p_kind: string }
        Returns: undefined
      }
      business_wallet_balance_cents: {
        Args: { p_user: string }
        Returns: number
      }
      business_wallet_summary: {
        Args: never
        Returns: {
          balance_cents: number
          launch_credit_cents: number
          month_impressions: number
          month_spend_cents: number
          spend_cents: number
          topup_cents: number
        }[]
      }
      coach_has_grant: {
        Args: { p_client: string; p_need?: string }
        Returns: boolean
      }
      coach_has_grant_for: {
        Args: { p_client: string; p_coach: string; p_need?: string }
        Returns: boolean
      }
      generate_coach_grant_code: { Args: { p_scope?: string }; Returns: string }
      generate_jasper_link_code: { Args: never; Returns: string }
      import_whisper_meet_document: {
        Args: { p_document: Json; p_id: string; p_operation: string }
        Returns: {
          deleted: boolean
          document: Json | null
          id: string
          operation_id: string
          owner_id: string
          revision: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "whisper_private_notebooks"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      increment_helpful_report_count: {
        Args: { p_reporter: string }
        Returns: undefined
      }
      is_coach_of: { Args: { client_uid: string }; Returns: boolean }
      is_thread_member: {
        Args: { p_thread_id: string; p_user_id: string }
        Returns: boolean
      }
      is_whisper_meeting_host: {
        Args: { p_meeting_id: string }
        Returns: boolean
      }
      is_whisper_meeting_member: {
        Args: { p_meeting_id: string }
        Returns: boolean
      }
      jasper_ai_conversations_v1: {
        Args: {
          p_action: string
          p_expected?: number
          p_id?: string
          p_offset?: number
          p_operation?: string
          p_payload?: string
          p_query?: string
          p_title?: string
        }
        Returns: Json
      }
      jasper_connect_all_scopes: { Args: never; Returns: string[] }
      jasper_connect_authorize: {
        Args: { p_app_name: string; p_client?: string; p_scopes?: string[] }
        Returns: Json
      }
      jasper_connect_check: {
        Args: { p_token: string }
        Returns: {
          app_name: string
          created_at: string
          created_via: string
          expires_at: string | null
          grantee_uid: string | null
          id: string
          kind: string
          last_used_at: string | null
          revoked_at: string | null
          scopes: string[]
          token_hash: string
          token_prefix: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "jasper_connect_tokens"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      jasper_connect_claim: { Args: { p_request_id: string }; Returns: Json }
      jasper_connect_claim_pkce: {
        Args: { p_code_verifier: string; p_request_id: string }
        Returns: Json
      }
      jasper_connect_coach_gate: {
        Args: {
          p_grantee: string
          p_kind: string
          p_need: string
          p_owner: string
        }
        Returns: Json
      }
      jasper_connect_connections: { Args: never; Returns: Json }
      jasper_connect_delete: {
        Args: { p_id: string; p_resource: string; p_token: string }
        Returns: Json
      }
      jasper_connect_events_page: {
        Args: {
          p_after?: number
          p_context?: string
          p_limit?: number
          p_token: string
        }
        Returns: Json
      }
      jasper_connect_fetch: {
        Args: {
          p_cursor?: number
          p_limit?: number
          p_resource: string
          p_since?: string
          p_token: string
        }
        Returns: Json
      }
      jasper_connect_grocery_get: {
        Args: { p_plan_id?: string; p_token: string }
        Returns: Json
      }
      jasper_connect_grocery_set: {
        Args: { p_items: Json; p_plan_id: string; p_token: string }
        Returns: Json
      }
      jasper_connect_history: {
        Args: {
          p_after?: string
          p_context?: string
          p_id?: string
          p_limit?: number
          p_resource: string
          p_token: string
        }
        Returns: Json
      }
      jasper_connect_inbox: { Args: never; Returns: Json }
      jasper_connect_int: { Args: { k: string; p: Json }; Returns: number }
      jasper_connect_link_is_current: {
        Args: {
          p_created: string
          p_grantee: string
          p_kind: string
          p_owner: string
          p_via: string
        }
        Returns: boolean
      }
      jasper_connect_mint: {
        Args: {
          p_app_name: string
          p_expires_days?: number
          p_scopes: string[]
        }
        Returns: Json
      }
      jasper_connect_mint_internal: {
        Args: {
          p_app_name: string
          p_expires_days?: number
          p_grantee: string
          p_kind: string
          p_owner: string
          p_scopes: string[]
          p_via: string
        }
        Returns: Json
      }
      jasper_connect_mutate_once: {
        Args: {
          p_id?: string
          p_key: string
          p_method: string
          p_payload?: Json
          p_resource: string
          p_token: string
        }
        Returns: Json
      }
      jasper_connect_num: { Args: { k: string; p: Json }; Returns: number }
      jasper_connect_publish_events: {
        Args: { p_owner: string }
        Returns: boolean
      }
      jasper_connect_recipes_delete: {
        Args: { p_id: string; p_token: string }
        Returns: Json
      }
      jasper_connect_recipes_list: {
        Args: { p_limit?: number; p_since?: string; p_token: string }
        Returns: Json
      }
      jasper_connect_recipes_write: {
        Args: { p_body: Json; p_token: string }
        Returns: Json
      }
      jasper_connect_request: {
        Args: {
          p_app_name: string
          p_kind?: string
          p_scopes?: string[]
          p_target_username?: string
        }
        Returns: Json
      }
      jasper_connect_request_pkce: {
        Args: {
          p_app_name: string
          p_code_challenge: string
          p_kind: string
          p_scopes: string[]
          p_target_username: string
        }
        Returns: Json
      }
      jasper_connect_required_scope: {
        Args: { p_resource: string }
        Returns: string
      }
      jasper_connect_respond: {
        Args: { p_approve: boolean; p_request_id: string; p_scopes?: string[] }
        Returns: Json
      }
      jasper_connect_revoke: { Args: { p_id: string }; Returns: undefined }
      jasper_connect_scope_ok: {
        Args: { p_required: string; p_scopes: string[] }
        Returns: boolean
      }
      jasper_connect_token_info: { Args: { p_token: string }; Returns: Json }
      jasper_connect_ts: { Args: { k: string; p: Json }; Returns: string }
      jasper_connect_txt: { Args: { k: string; p: Json }; Returns: string }
      jasper_connect_uuid: { Args: { k: string; p: Json }; Returns: string }
      jasper_connect_webhook_ack: {
        Args: {
          p_cursor: number
          p_dispatch_key: string
          p_ok: boolean
          p_status?: number
          p_webhook_id: string
        }
        Returns: Json
      }
      jasper_connect_webhook_ack_v2: {
        Args: {
          p_delivery_id: string
          p_dispatch_key: string
          p_ok: boolean
          p_status?: number
          p_webhook_id: string
        }
        Returns: Json
      }
      jasper_connect_webhook_delete: {
        Args: { p_id: string; p_token: string }
        Returns: Json
      }
      jasper_connect_webhook_due: {
        Args: {
          p_dispatch_key: string
          p_max_events?: number
          p_max_webhooks?: number
        }
        Returns: Json
      }
      jasper_connect_webhook_due_v2: {
        Args: {
          p_dispatch_key: string
          p_max_events?: number
          p_max_webhooks?: number
        }
        Returns: Json
      }
      jasper_connect_webhook_list: { Args: { p_token: string }; Returns: Json }
      jasper_connect_webhook_register: {
        Args: { p_events?: string[]; p_token: string; p_url: string }
        Returns: Json
      }
      jasper_connect_write: {
        Args: { p_payload: Json; p_resource: string; p_token: string }
        Returns: Json
      }
      jasper_connect_write_scope: {
        Args: { p_resource: string }
        Returns: string
      }
      jasper_disconnect_linked_accounts: { Args: never; Returns: Json }
      jasper_intelligence_action_v1: {
        Args: {
          p_action: string
          p_expected?: number
          p_owner: string
          p_payload?: Json
          p_workspace: string
        }
        Returns: Json
      }
      jasper_link_intent_claim: {
        Args: { p_code_verifier: string; p_id: string }
        Returns: Json
      }
      jasper_link_intent_create: {
        Args: { p_code_challenge: string; p_id: string; p_owner: string }
        Returns: Json
      }
      jasper_link_intent_inspect: { Args: { p_id: string }; Returns: Json }
      jasper_link_intent_respond: {
        Args: { p_approve: boolean; p_consent_version: string; p_id: string }
        Returns: Json
      }
      jasper_link_lock: { Args: { p_uid: string }; Returns: undefined }
      jasper_marketplace_get: { Args: { p_id: string }; Returns: Json }
      jasper_marketplace_import: {
        Args: { p_template_id: string; p_token: string }
        Returns: Json
      }
      jasper_marketplace_list: {
        Args: {
          p_author?: string
          p_kind?: string
          p_limit?: number
          p_query?: string
        }
        Returns: Json
      }
      jasper_marketplace_publish: {
        Args: {
          p_goal?: string
          p_kind: string
          p_payload: Json
          p_price_usd?: number
          p_purchase_url?: string
          p_summary?: string
          p_template_id?: string
          p_title: string
          p_top_level?: Json
        }
        Returns: Json
      }
      jasper_marketplace_unpublish: {
        Args: { p_template_id: string }
        Returns: Json
      }
      jasper_notes_task_v1: {
        Args: {
          p_action: string
          p_expected?: number
          p_id?: string
          p_payload?: Json
        }
        Returns: Json
      }
      jasper_permissions_v1: {
        Args: { p_action?: string; p_expected?: number; p_values?: Json }
        Returns: Json
      }
      jasper_personality_v1: {
        Args: {
          p_action?: string
          p_expected?: number
          p_generation?: string
          p_key?: string
          p_quote?: string
          p_source?: string
          p_value?: string
        }
        Returns: Json
      }
      jasper_private_item_v1: {
        Args: {
          p_action: string
          p_expected?: number
          p_id?: string
          p_kind: string
          p_offset?: number
          p_payload?: Json
          p_title?: string
        }
        Returns: Json
      }
      jasper_record_verified_subscription: {
        Args: {
          p_checked_at: string
          p_expires_at: string
          p_has_max: boolean
          p_product_id: string
          p_source: string
          p_user_id: string
        }
        Returns: undefined
      }
      jasper_refresh_profile_rollups: {
        Args: { p_user: string }
        Returns: undefined
      }
      jasper_reserve_ai_call: { Args: { p_feature: string }; Returns: Json }
      jasper_try_decode_blob: { Args: { p_blob: string }; Returns: Json }
      jasper_uid_for: { Args: { p_uid?: string }; Returns: string }
      jasper_work_resolve_v1: {
        Args: { p_input: Json; p_owner: string }
        Returns: Json
      }
      jasper_work_v1: {
        Args: { p_action: string; p_input?: Json; p_owner: string }
        Returns: Json
      }
      join_whisper_meeting: {
        Args: { p_meeting_id: string; p_username?: string }
        Returns: undefined
      }
      knot_background_snapshot: {
        Args: {
          p_before_at?: string
          p_before_id?: string
          p_generation: string
          p_ids?: string[]
          p_owner: string
          p_scan?: boolean
        }
        Returns: Json
      }
      knot_set_background_grant: {
        Args: {
          p_direct_messages: boolean
          p_enabled: boolean
          p_groups: boolean
          p_meet_plans: boolean
        }
        Returns: Json
      }
      my_clients: {
        Args: never
        Returns: {
          client_uid: string
          granted_at: string
          scope: string
        }[]
      }
      my_coaches: {
        Args: never
        Returns: {
          coach_uid: string
          granted_at: string
          scope: string
        }[]
      }
      redeem_coach_grant_code: {
        Args: { p_code: string; p_scope?: string }
        Returns: string
      }
      redeem_jasper_link_code: { Args: { p_code: string }; Returns: string }
      reopen_whisper_meeting: {
        Args: { p_meeting_id: string; p_username?: string }
        Returns: undefined
      }
      revoke_all_coach_grants: { Args: never; Returns: undefined }
      revoke_coach_grant: { Args: { p_other_uid: string }; Returns: undefined }
      revoke_jasper_link: { Args: never; Returns: undefined }
      save_private_notebook: {
        Args: {
          p_deleted?: boolean
          p_document: Json
          p_id: string
          p_operation: string
          p_revision: number
        }
        Returns: {
          deleted: boolean
          document: Json | null
          id: string
          operation_id: string
          owner_id: string
          revision: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "whisper_private_notebooks"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      send_friend_request: {
        Args: {
          p_from_username: string
          p_to_user_id: string
          p_to_username: string
        }
        Returns: undefined
      }
      whisper_appeal_correction: {
        Args: { p_body: string; p_correction_id: string }
        Returns: string
      }
      whisper_blind_answer_overlap: {
        Args: { a: Json; b: Json }
        Returns: number
      }
      whisper_blind_date_decide: {
        Args: { p_decision: string; p_room_code: string }
        Returns: Json
      }
      whisper_blind_date_finish: {
        Args: { p_recap?: Json; p_revealed?: boolean; p_room_code: string }
        Returns: undefined
      }
      whisper_blind_date_history: { Args: never; Returns: Json[] }
      whisper_blind_date_join: {
        Args: { p_answers?: Json; p_username?: string }
        Returns: Json
      }
      whisper_blind_date_leave: { Args: never; Returns: undefined }
      whisper_blind_date_open: {
        Args: { p_room_code: string; p_source?: string }
        Returns: Json
      }
      whisper_blind_date_poll: { Args: never; Returns: Json }
      whisper_blind_queue_count: { Args: never; Returns: number }
      whisper_can_contact: {
        Args: { p_recipient: string; p_sender: string }
        Returns: boolean
      }
      whisper_can_view_post_author: {
        Args: { p_author: string }
        Returns: boolean
      }
      whisper_chat_meet_admit: { Args: { event_id: string }; Returns: Json }
      whisper_chat_meet_cancel: { Args: { event_id: string }; Returns: Json }
      whisper_chat_meet_get: { Args: { event_id: string }; Returns: Json }
      whisper_chat_meet_join: { Args: { event_id: string }; Returns: Json }
      whisper_chat_meet_legacy_event: {
        Args: { event_id: string }
        Returns: boolean
      }
      whisper_chat_meet_legacy_message: {
        Args: { message_id: string }
        Returns: boolean
      }
      whisper_chat_meet_legacy_room: {
        Args: { meeting_id: string }
        Returns: boolean
      }
      whisper_chat_meet_lookup: { Args: { meeting_id: string }; Returns: Json }
      whisper_chat_meet_message_access: {
        Args: { message_id: string }
        Returns: boolean
      }
      whisper_chat_meet_permission: {
        Args: { action: string; expected_revision?: number; peer_id: string }
        Returns: Json
      }
      whisper_chat_meet_permissions: { Args: never; Returns: Json }
      whisper_chat_meet_recovery: {
        Args: { after_event?: string }
        Returns: Json
      }
      whisper_chat_meet_respond: {
        Args: { event_id: string; response_status: string }
        Returns: Json
      }
      whisper_chat_meet_retry: { Args: { event_id: string }; Returns: Json }
      whisper_chat_meet_room_access: {
        Args: { meeting_id: string }
        Returns: boolean
      }
      whisper_chat_meet_schedule: {
        Args: {
          conversation_kind: string
          ends_at: string
          group_id?: string
          operation_id: string
          peer_id?: string
          starts_at: string
          timezone: string
          title: string
        }
        Returns: Json
      }
      whisper_chat_meet_signal_access: {
        Args: { channel_topic: string }
        Returns: boolean
      }
      whisper_chat_meet_upcoming: {
        Args: { after_event?: string; range_end: string; range_start: string }
        Returns: Json
      }
      whisper_claim_device_token: {
        Args: {
          p_bundle_id?: string
          p_platform?: string
          p_sandbox?: boolean
          p_token: string
        }
        Returns: undefined
      }
      whisper_claim_voip_token: {
        Args: { p_bundle_id?: string; p_environment?: string; p_token: string }
        Returns: undefined
      }
      whisper_coach_proposals_expire: { Args: never; Returns: undefined }
      whisper_dating_blocked_between: {
        Args: { a: string; b: string }
        Returns: boolean
      }
      whisper_dating_dealbreakers_ok: {
        Args: { a_deal: Json; b_life: Json }
        Returns: boolean
      }
      whisper_dating_event_counts: {
        Args: { p_keys: string[] }
        Returns: {
          event_key: string
          going: number
          me: boolean
        }[]
      }
      whisper_dating_event_toggle: {
        Args: { p_event_key: string; p_going: boolean; p_username?: string }
        Returns: Json
      }
      whisper_dating_fits: {
        Args: {
          a: Database["public"]["Tables"]["whisper_dating_prefs"]["Row"]
          b: Database["public"]["Tables"]["whisper_dating_prefs"]["Row"]
        }
        Returns: boolean
      }
      whisper_dating_is_staff: { Args: never; Returns: boolean }
      whisper_dating_nearby: {
        Args: never
        Returns: {
          age: number
          city_label: string
          distance_km: number
          gender: string
          intent: string
          lifestyle: Json
          user_id: string
          username: string
          verified: boolean
        }[]
      }
      whisper_dating_report: {
        Args: {
          p_block?: boolean
          p_details?: string
          p_reason: string
          p_reported_username: string
          p_room_code?: string
        }
        Returns: Json
      }
      whisper_dating_verification_queue: {
        Args: never
        Returns: {
          created_at: string
          method: string
          selfie_url: string
          user_id: string
          username: string
        }[]
      }
      whisper_dating_verification_review: {
        Args: { p_approve: boolean; p_user_id: string }
        Returns: string
      }
      whisper_dating_verification_submit: {
        Args: {
          p_liveness_passed?: boolean
          p_method?: string
          p_selfie_url: string
          p_username?: string
        }
        Returns: Json
      }
      whisper_dating_verified: {
        Args: { p_usernames: string[] }
        Returns: string[]
      }
      whisper_disappearing_allowed: {
        Args: { p_recipient: string; p_sender: string }
        Returns: boolean
      }
      whisper_disappearing_claim: {
        Args: { p_actor: string; p_id: string }
        Returns: boolean
      }
      whisper_disappearing_finish: {
        Args: { p_actor: string; p_id: string }
        Returns: undefined
      }
      whisper_disappearing_list: {
        Args: { p_actor: string }
        Returns: {
          created_at: string
          display_name: string
          expires_at: string
          id: string
          mime: string
          opened_at: string
          recipient_id: string
          sender_id: string
          username: string
        }[]
      }
      whisper_disappearing_reserve: {
        Args: {
          p_actor: string
          p_id: string
          p_mime: string
          p_recipient: string
        }
        Returns: string
      }
      whisper_event_action_v1: {
        Args: { p_action: string; p_actor: string; p_input: Json }
        Returns: Json
      }
      whisper_get_message_reactions: {
        Args: { p_message_ids: string[] }
        Returns: {
          emoji: string
          message_id: string
          mine: boolean
          reaction_count: number
        }[]
      }
      whisper_group_history_identity_v1: {
        Args: {
          p_body: string
          p_created: string
          p_logical: string
          p_sender: string
        }
        Returns: string
      }
      whisper_group_history_v1: {
        Args: {
          p_before_at?: string
          p_before_id?: string
          p_group_id: string
          p_limit?: number
        }
        Returns: {
          cursor_at: string
          cursor_id: string
          messages: Json
        }[]
      }
      whisper_group_summaries_v1: {
        Args: {
          p_before_at?: string
          p_before_id?: string
          p_hidden_ids?: string[]
          p_limit?: number
        }
        Returns: {
          group_id: string
          last_created_at: string
          last_message: Json
          last_message_id: string
          participants: Json
          unread_count: number
        }[]
      }
      whisper_is_business_member: {
        Args: { business: string }
        Returns: boolean
      }
      whisper_is_friend: {
        Args: { p_owner: string; p_viewer: string }
        Returns: boolean
      }
      whisper_is_group_member: { Args: { slug: string }; Returns: boolean }
      whisper_is_reviewer: { Args: never; Returns: boolean }
      whisper_is_thought_participant: {
        Args: { p_thought_user_id: string; p_uid: string }
        Returns: boolean
      }
      whisper_km: {
        Args: { lat1: number; lat2: number; lng1: number; lng2: number }
        Returns: number
      }
      whisper_legacy_appeal_owner: {
        Args: { p_username: string }
        Returns: boolean
      }
      whisper_meet_invite_notes: {
        Args: {
          p_doc: string
          p_initial_update: string
          p_invitation: string
          p_meeting: string
          p_user: string
        }
        Returns: Json
      }
      whisper_notes_action: {
        Args: { p_action: string; p_doc: string; p_payload?: Json }
        Returns: Json
      }
      whisper_notes_briefing_links: {
        Args: {
          p_documents: string[]
          p_meetings: string[]
          p_people: string[]
        }
        Returns: Json
      }
      whisper_notes_context: { Args: { p_doc: string }; Returns: Json }
      whisper_notes_filing_sync: {
        Args: { p_change?: Json; p_legacy?: Json; p_migration?: string }
        Returns: Json
      }
      whisper_notes_for_meetings: {
        Args: { p_meetings: string[] }
        Returns: Json
      }
      whisper_notes_groups: { Args: { p_group?: string }; Returns: Json }
      whisper_notes_invite_person: {
        Args: {
          p_doc: string
          p_invitation: string
          p_role: string
          p_user: string
        }
        Returns: Json
      }
      whisper_notes_library: { Args: never; Returns: Json }
      whisper_notes_meeting_share: {
        Args: { p_action: string; p_meeting: string; p_payload?: Json }
        Returns: Json
      }
      whisper_notes_message: {
        Args: {
          p_body: string
          p_doc: string
          p_id: string
          p_quote?: string
          p_recipient: string
        }
        Returns: Json
      }
      whisper_notes_open_meeting: {
        Args: { p_notebook: string }
        Returns: Json
      }
      whisper_notes_owner_recordings: {
        Args: {
          p_after?: string
          p_after_id?: string
          p_archive?: string
          p_document: string
          p_limit?: number
        }
        Returns: Json
      }
      whisper_notes_packet_seed: { Args: { p: Json }; Returns: Json }
      whisper_notes_people: {
        Args: { p_ids?: string[]; p_query?: string }
        Returns: Json
      }
      whisper_notes_recordings:
        | { Args: { p_doc: string }; Returns: Json }
        | {
            Args: {
              p_before?: string
              p_before_id?: string
              p_document: string
              p_limit?: number
            }
            Returns: Json
          }
      whisper_notes_role: { Args: { p_doc: string }; Returns: string }
      whisper_notes_suggestions: {
        Args: { p_action: string; p_doc: string; p_payload?: Json }
        Returns: Json
      }
      whisper_notes_text_node: {
        Args: { p_level?: number; p_text: string }
        Returns: Json
      }
      whisper_owns_community: { Args: { slug: string }; Returns: boolean }
      whisper_public_post: { Args: { p_id: string }; Returns: boolean }
      whisper_public_profiles: {
        Args: { uids: string[] }
        Returns: {
          display_name: string
          id: string
          is_verified: boolean
          profile_image_url: string
          username: string
        }[]
      }
      whisper_reaction_target: {
        Args: { p_message_id: string }
        Returns: string
      }
      whisper_recompute_trusted_member: {
        Args: { target: string }
        Returns: undefined
      }
      whisper_relink_client_uid: {
        Args: { new_uid: string; old_uid: string }
        Returns: Json
      }
      whisper_review_correction: {
        Args: {
          p_explanation: string
          p_report_id: string
          p_sources: string[]
          p_state?: string
        }
        Returns: string
      }
      whisper_review_correction_appeal: {
        Args: {
          p_appeal_id: string
          p_explanation: string
          p_outcome: string
          p_sources: string[]
        }
        Returns: string
      }
      whisper_save_meeting_recap: {
        Args: {
          p_expected_summary: string
          p_meeting: string
          p_operation: string
          p_payload: Json
          p_summary: string
        }
        Returns: Json
      }
      whisper_set_group_theme: {
        Args: {
          p_expected_revision: number
          p_group_id: string
          p_operation_id: string
          p_theme: Json
        }
        Returns: {
          group_id: string
          operation_id: string
          revision: number
          theme: Json
          updated_at: string
          updated_by: string
        }
        SetofOptions: {
          from: "*"
          to: "whisper_group_themes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      whisper_set_message_reaction: {
        Args: { p_emoji: string; p_message_id: string; p_operation_id: string }
        Returns: undefined
      }
      whisper_sign_service: {
        Args: {
          p_action: string
          p_actor?: string
          p_id?: string
          p_payload?: Json
        }
        Returns: Json
      }
      whisper_submit_report: {
        Args: {
          p_context?: Json
          p_details?: string
          p_kind: string
          p_reason: string
          p_target_id?: string
          p_target_username?: string
        }
        Returns: string
      }
      whisper_teams_deliver_dm_v1: {
        Args: {
          p_expires_ms: number
          p_invitation: string
          p_recipient: string
          p_sender: string
          p_team: string
        }
        Returns: Json
      }
      whisper_teams_following_v1: { Args: { p_offset?: number }; Returns: Json }
      whisper_teams_jasper_action: {
        Args: {
          p_action: string
          p_expected?: number
          p_generation?: string
          p_payload?: Json
          p_scope: string
        }
        Returns: Json
      }
      whisper_teams_profile_photos_v1: {
        Args: { p_members: string[] }
        Returns: {
          profile_image_url: string
          user_id: string
        }[]
      }
      whisper_thread_summaries_v1: {
        Args: {
          p_before_at?: string
          p_before_id?: string
          p_hidden_ids?: string[]
          p_limit?: number
        }
        Returns: {
          conversation_kind: string
          last_body: string
          last_created_at: string
          last_from_me: boolean
          last_message: Json
          last_message_id: string
          peer_id: string
          peer_username: string
          unread_count: number
        }[]
      }
      whisper_toggle_message_reaction: {
        Args: { p_emoji: string; p_message_id: string; p_operation_id: string }
        Returns: undefined
      }
      whisper_update_push_preferences: {
        Args: { p_owner: string; p_patch: Json }
        Returns: Json
      }
      whisper_valid_message_reaction: {
        Args: { p_emoji: string }
        Returns: boolean
      }
      wpp_creator_months: {
        Args: { p_user: string }
        Returns: {
          month: string
          my_views: number
          revenue_cents: number
          total_views: number
        }[]
      }
      wpp_track_views: {
        Args: { p_creators: string[]; p_posts: string[] }
        Returns: undefined
      }
    }
    Enums: {
      whisper_admin_role: "owner" | "admin" | "moderator"
      whisper_application_status: "pending" | "approved" | "denied"
      whisper_calendar_event_type:
        | "meet"
        | "content_collab"
        | "training"
        | "event"
        | "deadline"
        | "other"
      whisper_meeting_status: "pending" | "approved" | "denied" | "cancelled"
      whisper_prospect_status:
        | "discovered"
        | "contacted"
        | "interested"
        | "meeting"
        | "ready"
        | "passed"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      whisper_admin_role: ["owner", "admin", "moderator"],
      whisper_application_status: ["pending", "approved", "denied"],
      whisper_calendar_event_type: [
        "meet",
        "content_collab",
        "training",
        "event",
        "deadline",
        "other",
      ],
      whisper_meeting_status: ["pending", "approved", "denied", "cancelled"],
      whisper_prospect_status: [
        "discovered",
        "contacted",
        "interested",
        "meeting",
        "ready",
        "passed",
      ],
    },
  },
} as const
