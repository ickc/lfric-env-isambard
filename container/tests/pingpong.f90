! container/tests/pingpong.f90 — the MPI check for the container.
!
! Written against mpi_f08 on purpose: LFRic's lfric_mpi_mod uses mpi_f08, and
! the f08 bindings are the part of an MPI library least covered by MPICH's ABI
! compatibility promise. A runtime library swap that passes a C hello-world can
! still break here.
!
! Prints which MPI library actually got loaded (MPI_Get_library_version) and
! the libfabric provider in use, then times a ping-pong between rank 0 and the
! LAST rank. Run with one rank per node on two nodes and that pair crosses the
! interconnect, so the bandwidth tells you whether you got Slingshot (cxi,
! ~20 GB/s) or fell back to TCP (~1 GB/s).
!
! Ends with PINGPONG_OK on rank 0 when every check passed.
program pingpong
  use mpi_f08
  implicit none
  integer, parameter :: nbytes = 8 * 1024 * 1024, reps = 50, warm = 5
  character(len=MPI_MAX_LIBRARY_VERSION_STRING) :: libver
  character(len=MPI_MAX_PROCESSOR_NAME) :: host
  character(len=64) :: prov
  character(len=1), allocatable :: buf(:)
  integer :: rank, nranks, peer, i, n, total, plen
  double precision :: t0, t1, lat_t0, lat_t1
  type(MPI_Status) :: st

  call MPI_Init()
  call MPI_Comm_rank(MPI_COMM_WORLD, rank)
  call MPI_Comm_size(MPI_COMM_WORLD, nranks)
  call MPI_Get_processor_name(host, n)

  ! Every rank contributes 1: a wrong total means the f08 reduction is broken.
  call MPI_Allreduce(1, total, 1, MPI_INTEGER, MPI_SUM, MPI_COMM_WORLD)

  if (rank == 0) then
    call MPI_Get_library_version(libver, n)
    n = index(libver, new_line('a'))
    if (n == 0) n = len_trim(libver) + 1
    write(*, '(a)') 'library: ' // libver(1:n - 1)
    call get_environment_variable('FI_PROVIDER', prov, plen)
    if (plen == 0) prov = '(unset)'
    write(*, '(a,i0,a,a)') 'ranks: ', nranks, '  FI_PROVIDER=', trim(prov)
  end if
  call MPI_Barrier(MPI_COMM_WORLD)
  write(*, '(a,i0,a,a)') 'rank ', rank, ' on ', trim(host)
  call MPI_Barrier(MPI_COMM_WORLD)

  if (total /= nranks) then
    if (rank == 0) write(*, '(a,i0,a,i0)') 'FAIL: allreduce gave ', total, ', expected ', nranks
    call MPI_Abort(MPI_COMM_WORLD, 1)
  end if

  if (nranks >= 2 .and. (rank == 0 .or. rank == nranks - 1)) then
    allocate(buf(nbytes))
    buf = 'x'
    peer = merge(nranks - 1, 0, rank == 0)
    ! Latency: 1-byte messages.
    do i = 1, reps + warm
      if (i == warm + 1) lat_t0 = MPI_Wtime()
      if (rank == 0) then
        call MPI_Send(buf, 1, MPI_CHARACTER, peer, 1, MPI_COMM_WORLD)
        call MPI_Recv(buf, 1, MPI_CHARACTER, peer, 1, MPI_COMM_WORLD, st)
      else
        call MPI_Recv(buf, 1, MPI_CHARACTER, peer, 1, MPI_COMM_WORLD, st)
        call MPI_Send(buf, 1, MPI_CHARACTER, peer, 1, MPI_COMM_WORLD)
      end if
    end do
    lat_t1 = MPI_Wtime()
    ! Bandwidth: 8 MiB messages.
    do i = 1, reps + warm
      if (i == warm + 1) t0 = MPI_Wtime()
      if (rank == 0) then
        call MPI_Send(buf, nbytes, MPI_CHARACTER, peer, 2, MPI_COMM_WORLD)
        call MPI_Recv(buf, nbytes, MPI_CHARACTER, peer, 2, MPI_COMM_WORLD, st)
      else
        call MPI_Recv(buf, nbytes, MPI_CHARACTER, peer, 2, MPI_COMM_WORLD, st)
        call MPI_Send(buf, nbytes, MPI_CHARACTER, peer, 2, MPI_COMM_WORLD)
      end if
    end do
    t1 = MPI_Wtime()
    if (rank == 0) then
      write(*, '(a,f10.2,a)') 'latency (1 B, half round trip): ', &
        (lat_t1 - lat_t0) / (2 * reps) * 1d6, ' us'
      write(*, '(a,f10.2,a)') 'bandwidth (8 MiB):               ', &
        2d0 * reps * nbytes / (t1 - t0) / 1d9, ' GB/s'
    end if
  end if

  call MPI_Barrier(MPI_COMM_WORLD)
  if (rank == 0) write(*, '(a)') 'PINGPONG_OK'
  call MPI_Finalize()
end program pingpong
