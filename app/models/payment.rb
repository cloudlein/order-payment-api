class Payment < ApplicationRecord
  belongs_to :order

  enum :status,  { pending: "pending", paid: "paid", failed: "failed", refunded: "refunded" }, default: "pending"

  validates :gross_amount, numericality: { greater_than: 0 }, allow_nil: true

  validates :midtrans_transaction_id, uniqueness: true, allow_nil: true

  after_update :sync_order_status

  private

  def sync_order_status
    return unless saved_change_to_status?
    _from, to = saved_change_to_status
    return unless to == "paid"

    order.update!(status: "completed")
  end
end
