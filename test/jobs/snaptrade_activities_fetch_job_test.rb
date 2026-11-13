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
end
