#!/usr/bin/env python

#/*******************************************************************************
# Copyright (c) 2012 IBM Corp.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#/*******************************************************************************

'''
Created on Nov 06, 2011

Thread Pool Library

@author: Emilio Monti (ActiveState Code Recipe)
'''

from Queue import Queue
from threading import Thread
from time import sleep

class Worker(Thread):
    """Thread executing tasks from a given tasks queue"""
    def __init__(self, tasks):
        Thread.__init__(self)
        self.tasks = tasks
        self.daemon = True
        self.abort = False
        self.aborted = False
        self.start()

    def run(self):
        while True:
            func, args, kargs = self.tasks.get()
            try: 
                self.abort = False
                self.aborted = False
                func(*args, **kargs)
                self.aborted = True
            except Exception, e:
                print e
            self.tasks.task_done()

class ThreadPool:
    """Pool of threads consuming tasks from a queue"""
    def __init__(self, num_threads):
        self.workers = []
        self.tasks = Queue(num_threads)
        for _ in range(num_threads): self.workers.append(Worker(self.tasks))

    def add_task(self, func, *args, **kargs):
        """Add a task to the queue"""
        self.tasks.put((func, args, kargs))
        
    def abort(self):
        for worker in self.workers :
            worker.abort = True
        while True :
            all_aborted = True 
            for worker in self.workers :
                if not worker.aborted :
                    all_aborted = False
                    break
            if all_aborted :
                break
            sleep(0.5)

    def wait_completion(self):
        """Wait for completion of all the tasks in the queue"""
        while self.tasks.unfinished_tasks > 0 :
            sleep(0.5)
