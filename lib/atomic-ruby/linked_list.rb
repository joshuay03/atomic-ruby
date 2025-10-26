# frozen_string_literal: true

module AtomicRuby
  class LinkedList
    Node = Data.define(:value, :next_node)

    def initialize(head = nil)
      @head = head
    end

    def prepend(value)
      self.class.new(Node.new(value, @head))
    end

    def first
      @head&.value
    end

    def rest
      self.class.new(@head&.next_node)
    end

    def empty?
      @head.nil?
    end

    def length
      count = 0
      current = @head
      while current
        count += 1
        current = current.next_node
      end
      count
    end
  end
end
