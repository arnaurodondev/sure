require "test_helper"

class SnaptradeActivitiesFetchJobTest < ActiveJob::TestCase
  test "a rate-limited Personal key retries no faster than every 15 seconds" do
    snaptrade_account = snaptrade_accounts(:fidelity_401k)
    snaptrade_account.snaptrade_item.update!(oauth_access_token: nil, oauth_token_type: SnaptradeItem::PERSONAL_KEY_TOKEN_TYPE)
    Provider::Snaptrade.any_instance.stubs(:get_account_activities).raises(Provider::Snaptrade::RateLimitError.new("Rate limit exceeded"))

    freeze_time do
      assert_enqueued_with job: SnaptradeActivitiesFetchJob, at: 15.seconds.from_now do
        SnaptradeActivitiesFetchJob.perform_now(snaptrade_account, start_date: 1.year.ago.to_date)
      end
    end
  end

  test "a Personal key still rate limited after the last retry is captured, not treated as an empty account" do
    snaptrade_account = snaptrade_accounts(:fidelity_401k)
    snaptrade_account.update!(activities_fetch_pending: true)
    snaptrade_account.snaptrade_item.update!(oauth_access_token: nil, oauth_token_type: SnaptradeItem::PERSONAL_KEY_TOKEN_TYPE)
    Provider::Snaptrade.any_instance.stubs(:get_account_activities).raises(Provider::Snaptrade::RateLimitError.new("Rate limit exceeded"))

    assert_no_enqueued_jobs(only: SnaptradeActivitiesFetchJob) do
      assert_difference -> { DebugLogEntry.where(provider_key: "snaptrade", level: "error").count }, 1 do
        SnaptradeActivitiesFetchJob.perform_now(snaptrade_account, start_date: 1.year.ago.to_date,
                                                retry_count: SnaptradeActivitiesFetchJob::MAX_RETRIES)
      end
    end

    entry = DebugLogEntry.order(:created_at).last
    assert_equal [ "SnaptradeActivitiesFetchJob", "provider_sync", snaptrade_account.snaptrade_item.family, snaptrade_account.id ],
                 [ entry.source, entry.category, entry.family, entry.metadata["snaptrade_account_id"] ]
    assert_not snaptrade_account.reload.activities_fetch_pending?
  end

  test "an account still empty after the last retry is not captured as a failure" do
    snaptrade_account = snaptrade_accounts(:fidelity_401k)
    Provider::Snaptrade.any_instance.stubs(:get_account_activities).returns([])

    assert_no_difference -> { DebugLogEntry.count } do
      SnaptradeActivitiesFetchJob.perform_now(snaptrade_account, start_date: 1.year.ago.to_date,
                                              retry_count: SnaptradeActivitiesFetchJob::MAX_RETRIES)
    end
  end
end
