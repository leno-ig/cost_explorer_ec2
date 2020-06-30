require 'aws-sdk-ec2'
require 'csv'

class CostExplorerEc2
  attr_reader :results, :client, :instances, :volumes, :snapshots, :images

  def initialize(region, akid, secret)
    @results = []
    @client = Aws::EC2::Client.new({
      region: region,
      credentials: Aws::Credentials.new(akid, secret)
    })
  end

  def describe_instances(params={})
    @instances ||= @client.describe_instances(params)
  end
  def describe_volumes(params={})
    @volumes ||= @client.describe_volumes(params)
  end
  def describe_snapshots(params={})
    @snapshots ||= @client.describe_snapshots(params)
  end
  def describe_images(params={})
    @images ||= @client.describe_images(params)
  end

  def generate_results
    return @results unless @results.empty?
    # describe resources
    describe_instances
    describe_volumes
    describe_snapshots(owner_ids: ['self'])
    describe_images(owners: ['self'])

    # index by instance_id
    instances = @instances.reservations.inject({}) do |a, reservation|
      reservation.instances.inject(a) do |b, instance|
        b.merge(instance.instance_id => instance)
      end
    end
    # snapshots array
    snapshots = @snapshots.snapshots.to_a
    # index by snapshot_id
    images = @images.images.inject({}) do |a, image|
      image.block_device_mappings.inject(a) do |b, device|
        b.merge(device.ebs&.snapshot_id => image)
      end
    end

    @volumes.volumes.each do |volume|
      result = Result.new

      device = volume.attachments.first
      instance = instances[device&.instance_id]
      (matches, snapshots) = snapshots.partition do |snapshot|
        volume.volume_id == snapshot.volume_id
      end

      # instance attributes
      if instance
        result.instance_id = instance.instance_id
        result.instance_name = instance.tags.find{|tag|tag.key == 'Name'}&.value
        result.instance_type = instance.instance_type
        result.instance_state = instance.state.name
        result.device_name = device.device
      end

      # volume attributes
      result.volume_id = volume.volume_id
      result.volume_size = volume.size
      result.volume_state = volume.state
      result.volume_type = volume.volume_type

      if matches.empty?
        @results << result
      else
        matches.each do |snapshot|
          tmp = result.dup

          # snapshot attributes
          tmp.snapshot_id = snapshot.snapshot_id
          tmp.snapshot_state = snapshot.state
          tmp.snapshot_size = snapshot.volume_size

          # image attributes
          if (image = images[snapshot.snapshot_id])
            tmp.image_id = image.image_id
            tmp.image_name = image.name
          end
          
          @results << tmp
        end
      end
    end

    # unmatch snapshots
    snapshots.each do |snapshot|
      result = Result.new

      # snapshot attributes
      result.snapshot_id = snapshot.snapshot_id
      result.snapshot_state = snapshot.state
      result.snapshot_size = snapshot.volume_size
      
      # image attributes
      if (image = images[snapshot.snapshot_id])
        result.image_id = image.image_id
        result.image_name = image.name
      end

      @results << result
    end

    @results
  end

  def to_csv(path=nil)
    generate_results if @results.empty?
    csv = CSV.generate(headers: Result::ATTRS, write_headers: true) do |row|
      @results.each do |result|
        row << result.attributes
      end
    end

    if path
      open(path, 'w') do |io|
        io.write csv
      end
    end

    csv
  end

  class Result
    ATTRS = [
      :instance_id, :instance_name, :instance_type, :instance_state, :device_name, 
      :volume_id, :volume_size, :volume_state, :volume_type, 
      :snapshot_id, :snapshot_state, :snapshot_size,
      :image_id, :image_name,
    ]
    attr_accessor *ATTRS
    def attributes
      ATTRS.inject({}) do |hash, attr|
        hash.merge(attr => self.send(attr))
      end
    end
  end
end